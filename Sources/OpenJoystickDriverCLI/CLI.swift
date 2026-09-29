import Foundation
import OpenJoystickDriverKit

package struct CLI {
  package init() {}

  @MainActor
  package func run(arguments: ArraySlice<String>) async {
    installCLIShutdownHandlers()
    do {
      let grammar = try CLIGrammar(arguments: Array(arguments))
      try await grammar.run()
    } catch {
      Self.report(error)
      exit(Self.exitCode(for: error))
    }
  }

  static func exitCode(for error: any Error) -> Int32 {
    switch error {
    case let error as CLIExit: error.code
    case is CLIParseError: CLIParseError.exitCode
    default: 1
    }
  }

  private static func report(_ error: any Error) {
    switch error {
    case is CLIExit: return
    case let error as CLIParseError:
      fputs("error: \(error.localizedDescription)\n", stderr)
      fputs("\n\(CLIHelp.text)\n", stderr)
    default: fputs("error: \(error.localizedDescription)\n", stderr)
    }
  }
}
