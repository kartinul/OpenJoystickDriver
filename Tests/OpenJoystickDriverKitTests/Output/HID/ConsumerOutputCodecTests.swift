import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension ControllerOutputCommand {
  /// The bounded set-rumble a consumer report requests, from its channel bytes.
  static func consumerRumble(
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    durationMs: Int = 250
  ) -> Self {
    let bytes: [PhysicalRumbleMotor: UInt8] = [
      .leftMain: left, .rightMain: right, .leftTrigger: leftTrigger, .rightTrigger: rightTrigger,
    ]
    return .setRumble(RumbleIntensities(bytes: bytes), duration: .milliseconds(durationMs))
  }
}

/// Decodes one output report through the consumer output codec.
func consumerOutput(
  _ reportID: UInt32,
  _ bytes: [UInt8],
  in format: some VirtualGamepadReportFormat
) throws -> ControllerOutputCommand {
  let request = try VirtualHostReportRequest(type: .output, reportID: reportID, bytes: bytes)
  return try ConsumerOutputCodec.decode(request, in: format)
}

struct ConsumerOutputCodecTests {
  @Test
  func allZeroConsumerReportsStopRumble() throws {
    // Every motor activated at zero, with a nonzero duration.
    #expect(
      try consumerOutput(3, [0x03, 0x0F, 0, 0, 0, 0, 5, 0, 0], in: XboxGeckoHIDReportFormat())
        == .stopRumble
    )
    // Nonzero intensities whose activation bits are clear.
    #expect(
      try consumerOutput(3, [0x03, 0x00, 10, 20, 30, 40, 5, 0, 0], in: XboxGeckoHIDReportFormat())
        == .stopRumble
    )
    #expect(
      try consumerOutput(0, [0x08, 0x00, 0, 0], in: OJDGenericGamepadFormat()) == .stopRumble
    )
    #expect(
      try consumerOutput(0, [0x4F, 0, 0, 0, 0, 0xF4, 0x01], in: OJDGenericGamepadFormat())
        == .stopRumble
    )
  }

  @Test
  func rumbleDurationComesFromTheReport() throws {
    let intensities = RumbleIntensities(bytes: [.leftMain: 1, .rightMain: 255])
    #expect(intensities.leftMain.rawValue == 257)
    #expect(intensities.rightMain == .max)
    // A duration byte of 0 is an immediate rumble, not a stop.
    #expect(
      try consumerOutput(3, [0x03, 0x0C, 0, 0, 1, 255, 0, 0, 0], in: XboxGeckoHIDReportFormat())
        == .setRumble(intensities, duration: .milliseconds(0))
    )
    #expect(
      try consumerOutput(0, [0x4F, 1, 255, 0, 0, 0, 0], in: OJDGenericGamepadFormat())
        == .setRumble(intensities, duration: .milliseconds(0))
    )
    // A longer OJD duration runs for the longest rumble a command may request.
    #expect(
      try consumerOutput(0, [0x4F, 1, 255, 0, 0, 0xFF, 0xFF], in: OJDGenericGamepadFormat())
        == .setRumble(intensities, duration: .milliseconds(maxRumbleDurationMs))
    )
    // A report without a duration field runs for the default duration.
    #expect(
      try consumerOutput(0, [0x4F, 1, 255, 0, 0], in: OJDGenericGamepadFormat())
        == .setRumble(
          intensities,
          duration: .milliseconds(ConsumerOutputCodec.defaultRumbleDurationMs)
        )
    )
  }

  @Test
  func shortReportsAreRejectedByTheCodec() throws {
    let xboxOne = try XboxGeckoHIDReportFormat()
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(3, [0x03, 0x0F, 10, 20, 30, 40], in: xboxOne)
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(0, [0x08, 0x00, 128], in: OJDGenericGamepadFormat())
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(0, [0x4F, 1, 2, 3], in: OJDGenericGamepadFormat())
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(0, [0x4F, 1, 2, 3, 4, 0x2C], in: OJDGenericGamepadFormat())
    }
    // The short Xbox 360 form is four or seven bytes; five bytes match neither.
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(0, [0x08, 0x00, 127, 255, 0], in: OJDGenericGamepadFormat())
    }
  }

  @Test
  func oversizedAndUndeclaredReportsAreRejectedByTheCodec() throws {
    #expect(throws: VirtualHostReportError.tooLarge) {
      try consumerOutput(0, [0x4F, 1, 2, 3, 4, 0xF4, 0x01, 0], in: OJDGenericGamepadFormat())
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(9, [0x09, 0x0F, 0, 0, 10, 20, 5, 0, 0], in: XboxGeckoHIDReportFormat())
    }
  }
}
