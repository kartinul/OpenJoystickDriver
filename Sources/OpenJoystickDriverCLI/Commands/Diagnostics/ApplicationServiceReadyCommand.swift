import Foundation
import OpenJoystickDriverKit

private enum ApplicationServiceReadyOutcome: Sendable {
  case ready
  case failed(String)
}

struct ApplicationServiceReadyCommand {
  let serviceCallTimeoutSeconds: Double

  func run() async throws {
    let client = ApplicationServiceClient()
    await client.connect(timeoutSeconds: serviceCallTimeoutSeconds)
    let outcome = await withTimeout(seconds: serviceCallTimeoutSeconds) {
      () async -> ApplicationServiceReadyOutcome in
      do {
        _ = try await client.getStatus()
        return .ready
      } catch { return .failed(error.localizedDescription) }
    }
    client.disconnect()
    guard let outcome else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.app_ready.not_ready",
          "The authenticated application service is not ready."
        )
      )
      throw CLIExit.failure
    }
    switch outcome {
    case .ready: print("ready")
    case .failed(let message):
      CLIOutput.error(message)
      throw CLIExit.failure
    }
  }
}
