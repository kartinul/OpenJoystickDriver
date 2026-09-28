import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerOutputCommandTests {
  @Test
  func protocolBytesRoundTripThroughUnipolarValues() {
    for byte in UInt8.min...UInt8.max {
      #expect(UnipolarValue(byte: byte).rawValue == UInt16(byte) * 257)
      #expect(UnipolarValue(byte: byte).byte == byte)
      // Ownership keeps a Double intensity and arbitration rounds it to the protocol byte.
      let intensity = Double(byte) / 255
      #expect(UnipolarValue(byte: UInt8((intensity * 255).rounded())).byte == byte)
    }
    #expect(UnipolarValue.max.byte == 255)
    #expect(UnipolarValue(128).byte == 0)
    #expect(UnipolarValue(129).byte == 1)
  }

  @Test
  func partialRumbleZeroesAndReportsTheChannelsTheControllerLacks() throws {
    let mains = PhysicalControllerOutputCapabilities.dualMainRumble
    let requested = RumbleIntensities(
      leftMain: UnipolarValue(byte: 0x40),
      rightMain: .min,
      leftTrigger: UnipolarValue(byte: 0x20),
      rightHaptic: .max
    )
    let admitted = try mains.admit(.setRumble(requested, duration: .held))
    #expect(
      admitted.command
        == .setRumble(RumbleIntensities(leftMain: UnipolarValue(byte: 0x40)), duration: .held)
    )
    #expect(admitted.droppedRumbleChannels == [.leftTrigger, .rightHaptic])

    let triggersOnly = RumbleIntensities(leftTrigger: .max, rightTrigger: .max)
    let dropped = try mains.admit(.setRumble(triggersOnly, duration: .milliseconds(0)))
    #expect(dropped.command == .setRumble(.off, duration: .milliseconds(0)))
    #expect(dropped.droppedRumbleChannels == [.leftTrigger, .rightTrigger])
    #expect(try mains.admit(.stopRumble) == (.stopRumble, []))
  }

  @Test
  func commandsWithoutTheirCapabilityAreUnsupported() {
    let none = PhysicalControllerOutputCapabilities.none
    let rumble = RumbleIntensities(rightTrigger: .max)
    let cases: [(ControllerOutputCommand, ControllerOutputCapability)] = [
      (.setRumble(rumble, duration: .held), .rumble(.rightTrigger)),
      (.setRumble(.off, duration: .held), .rumble(.leftMain)), (.stopRumble, .rumble(.leftMain)),
      (.setPlayerIndicator(.player1), .playerIndicator), (.setRGB(red: 1, green: 2, blue: 3), .rgb),
      (.setLightBrightness(.max), .lightBrightness),
      (.setAdaptiveTrigger(.right, .off), .adaptiveTrigger(.right)),
    ]
    for (command, capability) in cases {
      #expect(throws: ControllerOutputError.unsupportedCapability(capability)) {
        try none.admit(command)
      }
    }
    let leftTrigger = PhysicalControllerOutputCapabilities(adaptiveTriggers: [.left])
    #expect(throws: ControllerOutputError.unsupportedCapability(.adaptiveTrigger(.right))) {
      try leftTrigger.admit(.setAdaptiveTrigger(.right, .off))
    }
    #expect(throws: Never.self) { try leftTrigger.admit(.setAdaptiveTrigger(.left, .off)) }
  }

  @Test
  func driversWithoutAnOutputThrowUnsupportedCapability() {
    #expect(throws: ControllerOutputError.unsupportedCapability(.rgb)) {
      try XIDDriver().encode(.setRGB(red: 1, green: 2, blue: 3))
    }
    #expect(throws: ControllerOutputError.unsupportedCapability(.rumble(.leftMain))) {
      try FlydigiDriver().encode(.stopRumble)
    }
    #expect(throws: ControllerOutputError.unsupportedCapability(.lightBrightness)) {
      try DualSenseDriver().encode(.setLightBrightness(.max))
    }
  }
}
