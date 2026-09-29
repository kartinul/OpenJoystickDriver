import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct VirtualProfileCommandTests {
  @Test
  func reportsTheLiveProfileAndItsSource() {
    let result = VirtualHIDProfileOverrideResult(
      requested: .generic,
      live: .generic,
      source: "override",
      failure: nil
    )

    #expect(VirtualProfileCommand.liveText(result) == "Virtual HID profile: hid-generic (override)")
    #expect(VirtualProfileCommand.failureText(result) == nil)
  }

  @Test
  func reportsNoLiveProfileAndTheFailureCode() {
    let result = VirtualHIDProfileOverrideResult(
      requested: .xboxOneSBluetooth,
      live: nil,
      source: "override",
      failure: .outputDisabled
    )

    #expect(VirtualProfileCommand.liveText(result) == "Virtual HID profile: none (override)")
    #expect(
      VirtualProfileCommand.failureText(result)
        == "Virtual HID profile request failed: output-disabled"
    )
  }

  @Test
  func reportsTheActivationFailureDetail() {
    let result = VirtualHIDProfileOverrideResult(
      requested: .xboxOneSBluetooth,
      live: .generic,
      source: "automatic",
      failure: .activationFailed(detail: "backend timed out")
    )

    #expect(
      VirtualProfileCommand.failureText(result)
        == "Virtual HID profile request failed: activation-failed: backend timed out"
    )
  }
}
