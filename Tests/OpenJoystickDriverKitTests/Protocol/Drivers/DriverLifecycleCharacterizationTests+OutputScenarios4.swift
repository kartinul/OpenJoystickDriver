import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Neutralization write transcripts through DeviceManager, part two.
extension DriverLifecycleCharacterizationTests {
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
