import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Neutralization write transcripts through DeviceManager, part one.
extension DriverLifecycleCharacterizationTests {
  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationSixaxisUSB() async {
    #expect(
      await neutralizationSteps(Self.sixaxisUSB, locationID: 330) == [
        "suspend state=suspended failure=nil", "outputs=2", "  id=0x01 n=49",
        "    0101ff00ff000000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "  id=0x01 n=49",
        "    0101ff00ff000000000020ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationSixaxisBluetooth() async {
    #expect(
      await neutralizationSteps(Self.sixaxisBluetooth, locationID: 331) == [
        "suspend state=suspended failure=nil", "outputs=2", "  id=0x01 n=49",
        "    0101ff00ff000000000002ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "  id=0x01 n=49",
        "    0101ff00ff000000000020ff27100032ff27100032ff27100032ff2710003200",
        "    0000000000000000000000000000000000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationDualShock4USB() async {
    #expect(
      await neutralizationSteps(Self.dualShock4USB, locationID: 332) == [
        "suspend state=suspended failure=nil", "outputs=2", "  id=0x05 n=32",
        "    0501000000000000000000000000000000000000000000000000000000000000", "  id=0x05 n=32",
        "    0502000000000000400000000000000000000000000000000000000000000000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationDualShock4Bluetooth() async {
    #expect(
      await neutralizationSteps(Self.dualShock4Bluetooth, locationID: 333) == [
        "suspend state=suspended failure=nil", "outputs=2", "  id=0x11 n=78",
        "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89", "  id=0x11 n=78",
        "    11c4000200000000000040000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000f936e928", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationDualSenseUSB() async {
    #expect(
      await neutralizationSteps(Self.dualSenseUSB, locationID: 334) == [
        "suspend state=suspended failure=nil", "outputs=5", "  id=0x02 n=63",
        "    0203000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000", "  id=0x02 n=63",
        "    0208000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000", "  id=0x02 n=63",
        "    0204000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000", "  id=0x02 n=63",
        "    0200040000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000000000000000ff000000000000000000000000000000", "  id=0x02 n=63",
        "    0200100000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000000000000000000000000000000000000000000000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationDualSenseBluetooth() async {
    #expect(
      await neutralizationSteps(Self.dualSenseBluetooth, locationID: 335) == [
        "suspend state=suspended failure=nil", "outputs=5", "  id=0x31 n=78",
        "    3100100300000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000cc642e96", "  id=0x31 n=78",
        "    3110100800000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000191d5238", "  id=0x31 n=78",
        "    3120100400000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    00000000000000000000c59f6905", "  id=0x31 n=78",
        "    3130100004000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000ff0000000000000000000000000000",
        "    000000000000000000004457dc05", "  id=0x31 n=78",
        "    3140100010000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000002740a39e", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationSwitchUSB() async {
    #expect(
      await neutralizationSteps(Self.switchUSB, locationID: 336) == [
        "suspend state=suspended failure=nil", "outputs=2", "  id=0x10 n=10",
        "    10090001404000014040", "  id=0x01 n=12", "    010a00014040000140403000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationSwitchBluetooth() async {
    #expect(
      await neutralizationSteps(Self.switchBluetooth, locationID: 337) == [
        "suspend state=suspended failure=nil", "outputs=2", "  id=0x10 n=10",
        "    10090001404000014040", "  id=0x01 n=12", "    010a00014040000140403000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationSteamWired() async {
    #expect(
      await neutralizationSteps(Self.steamWired, locationID: 338) == [
        "suspend state=suspended failure=nil", "outputs=0", "features=1", "  id=0x00 n=64",
        "    87032d0000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationSteamDongle() async {
    #expect(
      await neutralizationSteps(Self.steamDongle, locationID: 339) == [
        "suspend state=suspended failure=nil", "outputs=0", "features=1", "  id=0x00 n=64",
        "    87032d0000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationFlydigi() async {
    #expect(
      await neutralizationSteps(Self.flydigi, locationID: 340) == [
        "suspend state=suspended failure=nil", "outputs=0", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationGameSirEnhancedHID() async {
    #expect(
      await neutralizationSteps(Self.gameSirEnhancedHID, locationID: 341) == [
        "suspend state=suspended failure=nil", "outputs=6", "  id=0x0f n=64",
        "    0f20665500000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000fc010000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000f930010514000080ff0080ff0080ff0080ff0080ff0080ff0080ff00",
        "    80ff0080ff0080ff0080ff0080ff0080ff0080ff008000000000000000000000", "  id=0x0f n=64",
        "    0f0320012930ff0080ff0080ff0080ff0080ff0080ff0080ff0080ff0080ff00",
        "    80ff0080ff0080ff0080ff0080ff0080ff0080ff008000000000000000000000", "  id=0x0f n=64",
        "    0f032001591cff0080ff0080ff0080ff0080ff0080ff0080ff0080ff0080ff00",
        "    80ff000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f03200000010200000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationGameSirEnhancedHID8K() async {
    #expect(
      await neutralizationSteps(Self.gameSirEnhancedHID8K, locationID: 342) == [
        "suspend state=suspended failure=nil", "outputs=6", "  id=0x0f n=64",
        "    0f20665500000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f03200001010000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f0320000c0300d2640000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000100300d2640000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000140300d2640000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f032000180300d2640000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "features=0",
      ]
    )
  }

  /// Suspending neutralizes every advertised output channel.
  @Test
  func neutralizationHidDescriptor() async {
    #expect(
      await neutralizationSteps(Self.hidDescriptor, locationID: 343) == [
        "suspend state=suspended failure=nil", "outputs=0", "features=0",
      ]
    )
  }
}
