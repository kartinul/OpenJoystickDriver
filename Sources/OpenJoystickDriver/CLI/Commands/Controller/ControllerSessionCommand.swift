import Foundation
import OpenJoystickDriverKit

struct ControllerSessionCommand {
  enum Action { case suspend, resume, disconnectWireless }

  let action: Action

  func run(arguments: [String]) {
    do {
      let selector = try ControllerSelector(arguments: arguments)
      let client = ApplicationServiceClient()
      client.connect()
      defer { client.disconnect() }
      let statusResult: Result<ApplicationServiceStatusPayload, Error> = runSyncResult {
        do { return .success(try await client.getStatus()) } catch { return .failure(error) }
      }
      let status = try statusResult.get()
      let device = try selector.resolve(devices: status.connectedDevices)
      let mutation: Result<Bool, Error> = runSyncResult {
        do {
          switch action {
          case .suspend:
            let result = try await client.suspendController(
              vendorID: device.vendorID,
              productID: device.productID,
              runtimeIdentifier: device.runtimeIdentifier
            )
            return .success(result.succeeded || result.failure == .alreadySuspended)
          case .resume:
            let result = try await client.resumeController(
              vendorID: device.vendorID,
              productID: device.productID,
              runtimeIdentifier: device.runtimeIdentifier
            )
            return .success(result.succeeded || result.failure == .alreadyActive)
          case .disconnectWireless:
            let result = try await client.disconnectWirelessController(
              vendorID: device.vendorID,
              productID: device.productID,
              runtimeIdentifier: device.runtimeIdentifier
            )
            guard result.succeeded else { throw Failure.wirelessDisconnectFailed(result) }
            return .success(result.succeeded)
          }
        } catch { return .failure(error) }
      }
      let succeeded = try mutation.get()
      guard succeeded else { throw Failure.sessionChangeRejected }
      switch action {
      case .suspend:
        print(
          CLILocalized.text(
            "cli.controller.disconnected",
            "Controller suspended from OpenJoystickDriver."
          )
        )
      case .resume:
        print(
          CLILocalized.text("cli.controller.resumed", "Controller resumed in OpenJoystickDriver.")
        )
      case .disconnectWireless:
        print(
          CLILocalized.text(
            "cli.controller.wirelessDisconnected",
            "Wireless controller disconnected."
          )
        )
      }
    } catch {
      CLIOutput.error(error.localizedDescription)
      exit(1)
    }
  }

  private enum Failure: Error, LocalizedError {
    case sessionChangeRejected
    case wirelessDisconnectFailed(WirelessControllerDisconnectResult)

    var errorDescription: String? {
      switch self {
      case .sessionChangeRejected: return "The controller session could not be changed."
      case .wirelessDisconnectFailed(let result):
        let stage = result.failedStage?.rawValue ?? "disconnect-wireless-controller"
        let cause = result.detail ?? result.failure?.rawValue ?? "unknown failure"
        let code = result.systemCode.map { " (system code \($0))" } ?? ""
        let recovery = result.recovery.map { " \($0)" } ?? ""
        return "Bluetooth controller disconnect failed during \(stage): \(cause)\(code).\(recovery)"
      }
    }
  }
}
