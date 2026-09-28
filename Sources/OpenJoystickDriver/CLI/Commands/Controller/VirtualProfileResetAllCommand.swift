import Foundation
import OpenJoystickDriverKit

/// `controller virtual reset --all`: clears every controller's virtual HID profile override,
/// including one an unreadable stored value would leave a per-model reset unable to clear, and
/// the retired compatibility identity keys.
struct VirtualProfileResetAllCommand {
  func run() {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }

    let ok =
      runSyncResult { do { return try await client.resetSettings() } catch { return false } }
      ?? false

    if !ok {
      CLIOutput.error(
        CLILocalized.text(
          "cli.controller.virtual.reset_all.failed",
          "Failed to reset settings. Launch the installed app and verify its permissions."
        )
      )
      exit(1)
    }

    print(
      CLILocalized.text(
        "cli.controller.virtual.reset_all.success",
        "OK: cleared every virtual HID profile override."
      )
    )
  }
}
