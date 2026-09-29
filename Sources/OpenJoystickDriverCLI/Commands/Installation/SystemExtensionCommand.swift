import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

private let ojdSystemExtensionID = ExtensionProbe.bundleIdentifier

struct SystemExtensionCommand {
  func run(arguments: [String]) throws {
    let subcommand = arguments.first ?? "status"
    switch subcommand {
    case "status": try printStatus()
    case "enable": try submitActivation()
    case "disable": try submitDeactivation()
    case "--help", "-h", "help": printHelp()
    default:
      CLIOutput.error(
        CLILocalized.format(
          "cli.extension.unknown_command",
          "Unknown extension command: %@",
          subcommand
        )
      )
      printHelp()
      throw CLIExit.failure
    }
  }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.extension.help",
        """
        Usage: OpenJoystickDriver --headless extension <status|enable|disable>

        Commands:
          status     Show registered OpenJoystickDriver system extensions
          enable     Submit DriverKit system extension activation request
          disable    Submit DriverKit system extension deactivation request
        """
      )
    )
  }

  private func printStatus() throws {
    let status = ExtensionProbe.currentStatus()
    switch status.bundle {
    case .present:
      print(CLILocalized.text("cli.extension.present", "Embedded DriverKit extension: present"))
    case .missing:
      print(CLILocalized.text("cli.extension.missing", "Embedded DriverKit extension: missing"))
    case .invalid(let actualIdentifier):
      print(
        CLILocalized.format(
          "cli.extension.invalid",
          "Embedded DriverKit extension: invalid (%@)",
          actualIdentifier
        )
      )
    }

    switch status.registration {
    case .active(let record):
      print(CLILocalized.text("cli.extension.registration_active", "OS registration: active"))
      print(record)
    case .inactive(let record):
      print(
        CLILocalized.text(
          "cli.extension.registration_inactive",
          "OS registration: registered but inactive"
        )
      )
      print(record)
    case .absent:
      print(CLILocalized.text("cli.extension.registration_absent", "OS registration: absent"))
    case .unavailable(let reason):
      CLIOutput.diagnostic(
        CLILocalized.text("cli.extension.registration_unavailable", "OS registration: unavailable")
      )
      CLIOutput.error(reason)
      throw CLIExit.failure
    }
  }

  private func submitActivation() throws {
    try requireApplicationsBundle()
    try requireValidBundleSignature(action: "Install system extension")
    guard bundleContainsSystemExtension() else {
      CLIOutput.error(
        CLILocalized.format(
          "cli.extension.bundle_missing",
          "App bundle does not contain %@.dext",
          ojdSystemExtensionID
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.extension.bundle_missing_fix",
          "Fix: run ./Scripts/ojd build install dev, then retry from /Applications."
        )
      )
      throw CLIExit.failure
    }
    try submit(.activation)
  }

  private func submitDeactivation() throws {
    try requireApplicationsBundle()
    try requireValidBundleSignature(action: "Uninstall system extension")
    try submit(.deactivation)
  }

  private func submit(_ mode: SystemExtensionSubmission.Mode) throws {
    let submission = SystemExtensionSubmission(mode: mode)
    submission.start()
    let result = submission.wait(timeout: 60)
    switch result {
    case .completed(let message): CLIOutput.diagnostic(message)
    case .requiresApproval:
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.extension.approval_required",
          "System extension request submitted and requires approval in System Settings."
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.extension.open_approval",
          "Open System Settings > General > Login Items & Extensions > Driver Extensions."
        )
      )
    case .timedOut:
      CLIOutput.error(
        CLILocalized.text(
          "cli.extension.timeout",
          "System extension request did not finish within 60s."
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.extension.timeout_recovery",
          "Check System Settings for an approval prompt, then run extension status."
        )
      )
      throw CLIExit(code: 2)
    case .failed(let error):
      CLIOutput.error(error)
      throw CLIExit.failure
    }
  }

  private func bundleContainsSystemExtension() -> Bool {
    let bundlePath = Bundle.main.bundlePath
    let dextPath = bundlePath + "/Contents/Library/SystemExtensions/\(ojdSystemExtensionID).dext"
    return FileManager.default.fileExists(atPath: dextPath)
  }

}
