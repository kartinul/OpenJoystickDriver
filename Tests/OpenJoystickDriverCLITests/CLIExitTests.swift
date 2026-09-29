import Foundation
import Testing

@testable import OpenJoystickDriverCLI

struct CLIExitTests {
  private struct UnexpectedFailure: Error {}

  @Test
  func exitCodeMapsEachErrorKind() {
    #expect(CLI.exitCode(for: CLIExit.failure) == 1)
    #expect(CLI.exitCode(for: CLIExit(code: 2)) == 2)
    #expect(CLI.exitCode(for: CLIParseError.unknownCommand("bogus")) == 64)
    #expect(CLI.exitCode(for: UnexpectedFailure()) == 1)
  }

  @Test(arguments: [
    ["watch", "--bogus"], ["state", "--seconds", "5"], ["watch", "--seconds", "0"],
    ["watch", "--device"], ["watch", "1"], ["bogus"], [],
  ])
  func inputParseErrorsThrowFailure(arguments: [String]) {
    #expect(throws: CLIExit.failure) { try InputCommand().parse(arguments) }
  }

  @Test
  func inputHelpReturnsWithoutOptions() throws {
    #expect(try InputCommand().parse(["--help"]) == nil)
  }

  @Test(arguments: [
    ["--bogus"], ["--stream", "x"], ["show", "--lines", "0"], ["path", "--lines", "5"],
  ])
  func logsArgumentErrorsThrowFailure(arguments: [String]) {
    #expect(throws: CLIExit.failure) { try LogsCommand().run(arguments: arguments) }
  }

  @Test(arguments: [
    ["bogus"], ["request", "extra"], ["open", "input", "output"], ["open", "bogus"],
  ])
  func permissionsArgumentErrorsThrowFailure(arguments: [String]) async {
    await #expect(throws: CLIExit.failure) {
      try await PermissionsCommand(serviceCallTimeoutSeconds: 0.1).run(arguments: arguments)
    }
  }

  @Test
  func runtimeHealthRejectsOutOfRangeSeconds() async {
    await #expect(throws: CLIExit.failure) {
      try await RuntimeHealthCommand().run(arguments: ["--seconds", "0"])
    }
  }

  @Test
  func physicalOutputRejectsInvalidIdentifierBeforeConnecting() async {
    await #expect(throws: CLIExit.failure) {
      try await PhysicalOutputCommand(serviceCallTimeoutSeconds: 0.1).run(arguments: [
        "rumble", "0xZZ", "1",
      ])
    }
  }
}
