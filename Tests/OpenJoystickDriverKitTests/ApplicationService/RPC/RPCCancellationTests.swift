import Darwin
import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct LocalServiceRPCCancellationTests {
  @Test(.timeLimit(.minutes(1)))
  func cancellingACallToASilentServerEndsPromptlyWithCancellationError() async throws {
    let socketPath = temporarySocketPath()
    let listener = try silentListener(socketPath: socketPath)
    defer {
      Darwin.close(listener)
      unlink(socketPath)
    }

    let task = Task {
      let _: String = try await LocalServiceRPCClient.call(
        method: "neverAnswered",
        arguments: LocalServiceRPCEmptyArguments(),
        timeoutSeconds: 30,
        socketPath: socketPath
      )
    }
    try await Task.sleep(nanoseconds: 200_000_000)

    let cancellationStart = ContinuousClock.now
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ContinuousClock.now - cancellationStart < .seconds(2))
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellingConnectStopsRetryingAndLeavesTheClientDisconnected() async throws {
    let client = ApplicationServiceClient(socketPath: temporarySocketPath())
    let task = Task { await client.connect(timeoutSeconds: 30) }
    try await Task.sleep(nanoseconds: 300_000_000)

    let cancellationStart = ContinuousClock.now
    task.cancel()
    await task.value
    #expect(ContinuousClock.now - cancellationStart < .seconds(2))
    #expect(!client.isConnected)
  }

  /// A socket that accepts connections into its backlog but never reads or replies.
  private func silentListener(socketPath: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var address = try LocalServiceRPCTransport.socketAddress(path: socketPath)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, LocalServiceRPCTransport.socketAddressLength(path: socketPath))
      }
    }
    try #require(bound == 0)
    try #require(listen(descriptor, 4) == 0)
    return descriptor
  }

  private func temporarySocketPath() -> String {
    "/tmp/com.openjoystickdriver.test.\(UUID().uuidString).rpc"
  }
}
