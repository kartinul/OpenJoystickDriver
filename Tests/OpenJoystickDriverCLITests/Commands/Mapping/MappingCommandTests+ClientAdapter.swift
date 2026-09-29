import Foundation
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

extension MappingCommandTests {
  @Test
  func adapterUsesAuthenticatedRPCClientFlow() async throws {
    let socketPath = "/tmp/com.openjoystickdriver.mapping-cli.\(UUID().uuidString).rpc"
    let profile = makeProfile(name: "RPC")
    let expected = snapshot([profile])
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { processID in processID == getpid() },
      handler: { request, completion in
        #expect(request.method == "getRemappingSnapshot")
        do {
          completion(

            LocalServiceRPCResponse(result: try JSONEncoder().encode(expected), error: nil)
          )
        } catch {
          completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
        }
      }
    )
    try server.start()
    defer { server.stop() }
    let rpcClient = ApplicationServiceClient(socketPath: socketPath)
    await rpcClient.connect()

    #expect(rpcClient.isConnected)
    let output = try await MappingInvocation(arguments: ["list", "--json"]).execute(
      client: ApplicationMappingServiceClient(client: rpcClient)
    )
    #expect(output.contains("RPC"))
  }

  @Test
  func calibrationStatusRoundTripsThroughAuthenticatedCLIAdapter() async throws {
    let socketPath = "/tmp/com.openjoystickdriver.calibration-cli.\(UUID().uuidString).rpc"
    let identifier = "045e:028e:location:2"
    let payload = Data(
      """
      {"hasMotionBaseline":true,"isCollecting":false,
       "offsetDegreesPerSecond":{"x":1.25,"y":-2.5,"z":0.125}}
      """.utf8
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { $0 == getpid() },
      handler: { request, completion in
        #expect(request.method == "remappingMotionCalibration")
        do {
          let arguments = try JSONDecoder().decode(
            ApplicationServiceMotionCalibrationArguments.self,
            from: request.arguments
          )
          #expect(arguments.runtimeIdentifier == identifier)
          #expect(arguments.command == nil)
          completion(LocalServiceRPCResponse(result: payload, error: nil))
        } catch {
          completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
        }
      }
    )
    try server.start()
    defer { server.stop() }
    let rpcClient = ApplicationServiceClient(socketPath: socketPath)
    await rpcClient.connect()
    defer { rpcClient.disconnect() }
    let output = try await MappingInvocation(arguments: [
      "calibration", "status", "--controller", identifier,
    ]).execute(client: ApplicationMappingServiceClient(client: rpcClient))
    let status = try JSONDecoder().decode(
      RemappingMotionCalibrationStatus.self,
      from: Data(output.utf8)
    )
    #expect(status.hasMotionBaseline)
    #expect(!status.isCollecting)
    #expect(status.offsetDegreesPerSecond == ControllerMotionVector(x: 1.25, y: -2.5, z: 0.125))
  }

  @Test
  func importAndExportUseFilesWhileMutationsUseClient() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("input.json")
    let output = directory.appendingPathComponent("output.json")
    let profile = makeProfile(name: "Portable")
    try Data(try MappingRenderer.json(profile).utf8).write(to: input)
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: ["import", input.path]).execute(client: client)
    _ = try await MappingInvocation(arguments: [
      "export", profile.id.uuidString, "--output", output.path,
    ]).execute(client: client)
    #expect(await client.mutationCount == 1)
    #expect(
      try JSONDecoder().decode(RemappingProfile.self, from: Data(contentsOf: output)) == profile
    )
  }

  func makeProfile(name: String = "Desktop", bindings: [RemappingBinding] = []) -> RemappingProfile
  {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: bindings
    )
  }

  func snapshot(_ profiles: [RemappingProfile]) -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }
}
