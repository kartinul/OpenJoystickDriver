/// Ends a CLI command with a non-zero exit status.
///
/// The command has already written its diagnostics to stdout or stderr before throwing, so the
/// entry point prints nothing more and only maps the error to `code`.
struct CLIExit: Error, Equatable {
  static let failure = Self(code: 1)

  let code: Int32
}
