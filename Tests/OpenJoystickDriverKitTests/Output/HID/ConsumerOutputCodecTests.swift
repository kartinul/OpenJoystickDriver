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
    // The duration byte counts 10 ms units.
    #expect(
      try consumerOutput(3, [0x03, 0x0C, 0, 0, 1, 255, 50, 0, 0], in: XboxGeckoHIDReportFormat())
        == .setRumble(intensities, duration: .milliseconds(500))
    )
  }

  @Test
  func shortReportsAreRejectedByTheCodec() throws {
    let xboxOne = try XboxGeckoHIDReportFormat()
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(3, [0x03, 0x0F, 10, 20, 30, 40], in: xboxOne)
    }
  }

  @Test
  func oversizedAndUndeclaredReportsAreRejectedByTheCodec() throws {
    #expect(throws: VirtualHostReportError.tooLarge) {
      try consumerOutput(3, [0x03, 0x0F, 0, 0, 10, 20, 5, 0, 0, 0], in: XboxGeckoHIDReportFormat())
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(9, [0x09, 0x0F, 0, 0, 10, 20, 5, 0, 0], in: XboxGeckoHIDReportFormat())
    }
  }

  @Test
  func theInputOnlyGenericFormatRejectsEveryOutputReport() {
    // The former OJD vendor report, the short Xbox 360 forms, and a numbered Xbox One report.
    let reports: [(UInt32, [UInt8])] = [
      (0, [0x4F, 1, 2, 3, 4, 0xF4, 0x01]), (0, [0x4F, 1, 2, 3, 4]), (0, [0x08, 0x00, 10, 20]),
      (0, [0x08, 0x00, 10, 20, 0, 0, 0]), (3, [0x03, 0x0F, 0, 0, 10, 20, 5, 0, 0]),
    ]
    for (reportID, bytes) in reports {
      #expect(throws: VirtualHostReportError.unsupported) {
        try consumerOutput(reportID, bytes, in: OJDGenericGamepadFormat())
      }
    }
  }
}
