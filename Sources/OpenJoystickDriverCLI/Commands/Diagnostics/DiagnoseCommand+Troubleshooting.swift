import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

extension DiagnoseCommand {

  func printTroubleshooting() {
    CLIOutput.diagnostic(CLILocalized.text("cli.diagnose.troubleshooting", "Troubleshooting:"))
    CLIOutput.diagnostic(
      CLILocalized.text("cli.diagnose.troubleshoot_no_input", "  No input from controller?")
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.troubleshoot_input_monitoring",
        "    -> Grant Input Monitoring: System Settings -> Privacy & Security -> Input Monitoring"
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.troubleshoot_virtual_device",
        "  User-space virtual device unavailable?"
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.troubleshoot_accessibility",
        "    -> Grant Accessibility to OpenJoystickDriver in Privacy & Security"
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.troubleshoot_driverkit",
        "  DriverKit extension missing/broken?"
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.troubleshoot_rebuild",
        "    -> Run: ./Scripts/ojd build install dev"
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.text("cli.diagnose.troubleshoot_reporting", "  Reporting a controller issue?")
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.troubleshoot_report_command",
        "    -> Run: --headless diagnose report"
      )
    )
  }
}
