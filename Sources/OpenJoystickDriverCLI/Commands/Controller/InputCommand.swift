import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct InputCommand {
  static let nanosecondsPerSecond: UInt64 = 1_000_000_000
  static let nanosecondsPerMillisecond: UInt64 = 1_000_000

  func run(arguments: [String]) async throws {
    guard let options = try parse(arguments) else { return }
    let service = await ControllerInputDiagnosticService()
    let failure = await withCLIShutdownCleanup(
      { await service.disconnect() },
      { await execute(options, service: service) }
    )
    await service.disconnect()
    if let failure {
      CLIOutput.error(failure)
      throw CLIExit.failure
    }
  }
}

struct InputCommandFailure: LocalizedError, Sendable {
  let message: String

  init(_ message: String) { self.message = message }

  var errorDescription: String? { message }
}
