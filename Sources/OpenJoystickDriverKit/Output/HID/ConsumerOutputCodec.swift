import Foundation

/// Decodes the output reports a consumer sends to a virtual format into the output command it
/// requests. The Xbox One rumble report (report ID 3) is the only output report any format
/// declares; the generic format is input-only.
enum ConsumerOutputCodec {
  static let xboxOneReportID: UInt8 = 3
  static let xboxOneReportPayloadSize = 8

  /// Duration of a rumble report that carries none.
  static let defaultRumbleDurationMs = 250

  private static let rumbleActivationAllMotors: UInt8 = 0x0F
  private static let rumbleActivationLeftTrigger: UInt8 = 0x01
  private static let rumbleActivationRightTrigger: UInt8 = 0x02
  private static let rumbleActivationLeft: UInt8 = 0x04
  private static let rumbleActivationRight: UInt8 = 0x08
  private static let rumbleDurationByteMultiplier = 10

  /// The command an output report addressed to `format`'s output report requests. A report
  /// `format` does not declare is unsupported; one whose length or header does not match its
  /// report ID is malformed.
  static func decode(
    _ request: VirtualHostReportRequest,
    in format: some VirtualGamepadReportFormat
  ) throws(VirtualHostReportError) -> ControllerOutputCommand {
    guard let maximum = format.outputReportPayloadSize,
      request.reportID == format.outputReportID ?? 0
    else { throw .unsupported }
    let payload = request.payload
    guard payload.count <= maximum else { throw .tooLarge }
    switch request.reportID {
    case xboxOneReportID:
      guard payload.count == xboxOneReportPayloadSize else { throw .malformed }
      return activatedRumble(payload)
    default: throw .unsupported
    }
  }

  /// A rumble command from report bytes; all four channels at zero stop rumble.
  static func rumble(
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    durationMs: Int = defaultRumbleDurationMs
  ) -> ControllerOutputCommand {
    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(byte: left),
      rightMain: UnipolarValue(byte: right),
      leftTrigger: UnipolarValue(byte: leftTrigger),
      rightTrigger: UnipolarValue(byte: rightTrigger)
    )
    guard intensities != .off else { return .stopRumble }
    return .setRumble(intensities, duration: .milliseconds(durationMs))
  }

  /// Xbox One layout: an activation mask, then left trigger, right trigger, left, right
  /// and a duration in 10 ms units.
  private static func activatedRumble(_ bytes: [UInt8]) -> ControllerOutputCommand {
    let activation = bytes[0] & rumbleActivationAllMotors
    func channel(_ mask: UInt8, _ offset: Int) -> UInt8 {
      activation & mask != 0 ? bytes[offset] : 0
    }
    return rumble(
      left: channel(rumbleActivationLeft, 3),
      right: channel(rumbleActivationRight, 4),
      leftTrigger: channel(rumbleActivationLeftTrigger, 1),
      rightTrigger: channel(rumbleActivationRightTrigger, 2),
      durationMs: Int(bytes[5]) * rumbleDurationByteMultiplier
    )
  }
}
