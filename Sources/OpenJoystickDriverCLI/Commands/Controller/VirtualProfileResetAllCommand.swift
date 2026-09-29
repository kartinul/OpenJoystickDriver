import Foundation
import OpenJoystickDriverKit

/// `controller virtual reset --all`: clears every controller's virtual HID profile override,
/// including one an unreadable stored value would leave a per-model reset unable to clear, and
/// the retired virtual HID identity keys.
struct VirtualProfileResetAllCommand {
  func run() async throws {
    let client = ApplicationServiceClient()
    await client.connect()
    defer { client.disconnect() }

    let ok = (try? await client.resetSettings()) ?? false

    if !ok {
      CLIOutput.error(
        CLILocalized.text(
          "cli.controller.virtual.reset_all.failed",
          "Failed to reset settings. Launch the installed app and verify its permissions."
        )
      )
      throw CLIExit.failure
    }

    print(
      CLILocalized.text(
        "cli.controller.virtual.reset_all.success",
        "OK: cleared every virtual HID profile override."
      )
    )
  }
}
