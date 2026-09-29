import Foundation
import OpenJoystickDriverKit

/// Registers the main application to launch at login for the current user.
struct InstallCommand {
  func run() throws {
    try requireApplicationsBundle()
    try requireValidBundleSignature(
      action: CLILocalized.text("cli.login.install_action", "Install")
    )
    do {
      try ApplicationServiceManager.install()
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.login.install_success",
          "OpenJoystickDriver registered to launch at login."
        )
      )
    } catch {
      CLIOutput.error(
        CLILocalized.format(
          "cli.login.install_failed",
          "Could not register the login item: %@",
          error.localizedDescription
        )
      )
      throw CLIExit.failure
    }
  }
}
