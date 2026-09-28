import Foundation
import Testing

@testable import OpenJoystickDriverKit

// HID startup and presence steps captured from the current DeviceManager path.
extension DriverLifecycleCharacterizationTests {
  @Test
  func dualShock4BluetoothStartupStepOrder() async {
    #expect(
      await dualShock4BluetoothStartupSteps() == [
        "outputs=1", "  id=0x11 n=78",
        "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89", "features=0",
      ]
    )
  }

  @Test
  func sixaxisBluetoothStartupStepOrder() async {
    #expect(
      await sixaxisBluetoothStartupSteps() == [
        "outputs=0", "features=1", "  id=0xf4 n=5", "    f442030000",
      ]
    )
  }

  @Test
  func switchBluetoothStartupStepOrder() async {
    #expect(
      await switchBluetoothStartupSteps() == [
        "outputs=9", "  id=0x01 n=12", "    010000014040000140400330", "  id=0x01 n=12",
        "    010100014040000140404001", "  id=0x01 n=12", "    010200014040000140404801",
        "  id=0x01 n=16", "    01030001404000014040102060000018", "  id=0x01 n=16",
        "    01040001404000014040102680000014", "  id=0x01 n=16",
        "    01050001404000014040102060000018", "  id=0x01 n=16",
        "    01060001404000014040102680000014", "  id=0x01 n=16",
        "    01070001404000014040102060000018", "  id=0x01 n=16",
        "    01080001404000014040102680000014", "features=0",
      ]
    )
  }

  @Test
  func steamDonglePresenceStepOrder() async {
    #expect(
      await steamDonglePresenceSteps() == [
        "startup", "outputs=0", "features=1", "  id=0x00 n=64",
        "    b400000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "connected",
        "outputs=0", "features=3", "  id=0x00 n=64",
        "    b400000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8100000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8709070700080700301800000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  @Test
  func gameSirEnhancedHIDStartupStepOrder() async {
    #expect(
      await gameSirEnhancedHIDStartupSteps() == [
        "outputs=2", "  id=0x0f n=64",
        "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f04200000010000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "features=0",
      ]
    )
  }
}
