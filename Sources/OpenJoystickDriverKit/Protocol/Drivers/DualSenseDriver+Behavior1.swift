import Foundation

extension DualSenseDriver {
  public var defaultColor: (red: UInt8, green: UInt8, blue: UInt8)? { (0, 0, 255) }

  /// DualSense Edge function buttons and back paddles.
  public static let edgeControls: Set<ControlID> = [
    .paddleLeft1, .paddleRight1, .auxiliary1, .auxiliary2,
  ]

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan(validatesFeatureReplies: true) }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    let base: Set<ControlID> = [
      .guide, .leftTriggerButton, .rightTriggerButton, .touchpadClick, .microphone,
    ]
    let edge: Set<ControlID> = hasEdgeButtons ? Self.edgeControls : []
    return ControllerCapabilities(
      controls: ControlID.xboxLayout.union(base).union(edge),
      touchContactCount: 2,
      motion: true
    )
  }

  private enum ReportOffset {
    static let leftStickX = 0
    static let leftStickY = 1
    static let rightStickX = 2
    static let rightStickY = 3
    static let l2Trigger = 4
    static let r2Trigger = 5
    static let buttons0 = 7
    static let buttons1 = 8
    static let buttons2 = 9
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain],
      lightingFeatures: [.playerIndicator, .programmableColor],
      adaptiveTriggers: PhysicalAdaptiveTrigger.allCases
    )
  }

  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    [PhysicalHIDFeatureReadRequest(reportID: 0x05, length: 41)]
  }

  public func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    guard request.reportID == 5, request.length == 41, data.count == 41 else { return false }
    let bytes = Array(data)
    if isBluetoothVariant || connectionMode == .bluetooth {
      var crc = updateCRC32(0xFFFF_FFFF, byte: 0xA3)
      for byte in bytes.dropLast(4) { crc = updateCRC32(crc, byte: byte) }
      let expected =
        UInt32(bytes[37]) | (UInt32(bytes[38]) << 8) | (UInt32(bytes[39]) << 16)
        | (UInt32(bytes[40]) << 24)
      guard ~crc == expected else { return false }
    }
    guard let calibrated = SonyMotionCalibration.dualSenseFactory(bytes) else { return false }
    motionCalibration = calibrated.installed(after: motionCalibration)
    return true
  }

  /// Decodes one DualSense HID input report into the full controller state and its samples.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = try reportPayload(from: data)
    guard bytes.count >= 10 else { return nil }
    var next = state
    next.leftStick = StickPosition(
      x: normalizeHID(bytes[ReportOffset.leftStickX]),
      yDown: normalizeHID(bytes[ReportOffset.leftStickY])
    )
    next.rightStick = StickPosition(
      x: normalizeHID(bytes[ReportOffset.rightStickX]),
      yDown: normalizeHID(bytes[ReportOffset.rightStickY])
    )
    next.leftTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.l2Trigger]) / dualSenseTriggerMax
    )
    next.rightTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.r2Trigger]) / dualSenseTriggerMax
    )
    next.hat = mapHat(bytes[ReportOffset.buttons0] & 0x0F)
    for (offset, mask, control) in buttonTable {
      next.set(control, pressed: bytes[offset] & mask != 0)
    }
    let samples = SonySensorSamples.dualSense(
      bytes,
      receivedAt: receivedAt.nanoseconds,
      clock: &sensorClock,
      calibration: motionCalibration
    )
    next.recordTouch(samples.touch)
    state = next
    return ControllerEvent(
      timestamp: receivedAt,
      state: next,
      motion: samples.motion,
      touchFrames: samples.touch
    )
  }

  /// Payload byte, mask and PlayStation-label control of each button; Edge buttons only on Edge.
  private var buttonTable: [(Int, UInt8, ControlID)] {
    let base: [(Int, UInt8, ControlID)] = [
      (ReportOffset.buttons0, 0x10, .faceWest), (ReportOffset.buttons0, 0x20, .faceSouth),
      (ReportOffset.buttons0, 0x40, .faceEast), (ReportOffset.buttons0, 0x80, .faceNorth),
      (ReportOffset.buttons1, 0x01, .leftShoulder), (ReportOffset.buttons1, 0x02, .rightShoulder),
      (ReportOffset.buttons1, 0x04, .leftTriggerButton),
      (ReportOffset.buttons1, 0x08, .rightTriggerButton), (ReportOffset.buttons1, 0x10, .view),
      (ReportOffset.buttons1, 0x20, .menu), (ReportOffset.buttons1, 0x40, .leftStickClick),
      (ReportOffset.buttons1, 0x80, .rightStickClick), (ReportOffset.buttons2, 0x01, .guide),
      (ReportOffset.buttons2, 0x02, .touchpadClick), (ReportOffset.buttons2, 0x04, .microphone),
    ]
    guard hasEdgeButtons else { return base }
    return base + [
      (ReportOffset.buttons2, 0x10, .auxiliary1), (ReportOffset.buttons2, 0x20, .auxiliary2),
      (ReportOffset.buttons2, 0x40, .paddleLeft1), (ReportOffset.buttons2, 0x80, .paddleRight1),
    ]
  }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      return output(
        validFlag0: dualSenseCompatibleVibrationFlags,
        motorRight: intensities.rightMain.byte,
        motorLeft: intensities.leftMain.byte
      )
    case .stopRumble: return output(validFlag0: dualSenseCompatibleVibrationFlags)
    case .setPlayerIndicator(let indicator):
      let patterns: [PhysicalPlayerIndicator: UInt8] = [
        .off: 0, .player1: 0x04, .player2: 0x0A, .player3: 0x15, .player4: 0x1B,
      ]
      return output(
        validFlag1: dualSensePlayerIndicatorFlag,
        playerIndicator: patterns[indicator] ?? 0
      )
    case .setRGB(let red, let green, let blue):
      return output(validFlag1: dualSenseLightbarFlag, red: red, green: green, blue: blue)
    case .setAdaptiveTrigger(let trigger, let effect):
      let encoded = Self.encodedAdaptiveTriggerEffect(effect)
      switch trigger {
      case .left:
        return output(validFlag0: dualSenseLeftTriggerEffectFlag, leftTriggerEffect: encoded)
      case .right:
        return output(validFlag0: dualSenseRightTriggerEffectFlag, rightTriggerEffect: encoded)
      }
    case .setLightBrightness: throw .unsupportedCapability(command.capability)
    }
  }

  static func encodedAdaptiveTriggerEffect(_ effect: PhysicalAdaptiveTriggerEffect) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 11)
    guard (try? effect.validate()) != nil, effect.kind == .resistance else { return bytes }
    bytes[0] = 0x01
    bytes[1] = UInt8((effect.startPosition * 9).rounded())
    bytes[2] = UInt8((effect.strength * 8).rounded())
    return bytes
  }

  /// One output report carrying only the flagged fields.
  private func output(
    validFlag0: UInt8 = 0,
    validFlag1: UInt8 = 0,
    motorRight: UInt8 = 0,
    motorLeft: UInt8 = 0,
    rightTriggerEffect: [UInt8] = [UInt8](repeating: 0, count: 11),
    leftTriggerEffect: [UInt8] = [UInt8](repeating: 0, count: 11),
    playerIndicator: UInt8 = 0,
    red: UInt8 = 0,
    green: UInt8 = 0,
    blue: UInt8 = 0
  ) -> PhysicalOutputPlan {
    switch connectionMode {
    case .usb:
      var report = [UInt8](repeating: 0, count: dualSenseUSBOutputReportLength)
      report[0] = dualSenseUSBOutputReportID
      report[1] = validFlag0
      report[2] = validFlag1
      report[3] = motorRight
      report[4] = motorLeft
      report.replaceSubrange(11..<22, with: rightTriggerEffect)
      report.replaceSubrange(22..<33, with: leftTriggerEffect)
      report[44] = playerIndicator
      report[45] = red
      report[46] = green
      report[47] = blue
      let output = PhysicalHIDOutputReport(reportID: dualSenseUSBOutputReportID, bytes: report)
      return PhysicalOutputPlan(writes: [.hidOutput(output)])
    case .bluetooth:
      var report = [UInt8](repeating: 0, count: dualSenseBluetoothOutputReportLength)
      report[0] = dualSenseBluetoothOutputReportID
      report[1] = outputSequence << 4
      outputSequence = (outputSequence + 1) & 0x0F
      report[2] = dualSenseOutputTag
      report[3] = validFlag0
      report[4] = validFlag1
      report[5] = motorRight
      report[6] = motorLeft
      report.replaceSubrange(13..<24, with: rightTriggerEffect)
      report.replaceSubrange(24..<35, with: leftTriggerEffect)
      report[46] = playerIndicator
      report[47] = red
      report[48] = green
      report[49] = blue
      let crc = dualSenseOutputCRC32(report: report)
      report[74] = UInt8(truncatingIfNeeded: crc)
      report[75] = UInt8(truncatingIfNeeded: crc >> 8)
      report[76] = UInt8(truncatingIfNeeded: crc >> 16)
      report[77] = UInt8(truncatingIfNeeded: crc >> 24)
      let output = PhysicalHIDOutputReport(
        reportID: dualSenseBluetoothOutputReportID,
        bytes: report
      )
      return PhysicalOutputPlan(writes: [.hidOutput(output)])
    }
  }

  private func reportPayload(from data: Data) throws -> [UInt8] {
    let bytes = Array(data)
    if bytes.first == dualSenseUSBInputReportID, bytes.count >= dualSenseUSBInputReportLength {
      connectionMode = .usb
      return Array(bytes.dropFirst())
    }
    if bytes.first == dualSenseBluetoothInputReportID,
      bytes.count >= dualSenseBluetoothInputReportLength
    {
      try validateBluetoothCRC(report: bytes)
      connectionMode = .bluetooth
      return Array(bytes.dropFirst(2).dropLast(4))
    }
    if bytes.first == dualSenseBluetoothHIDInputTransaction,
      bytes.dropFirst().first == dualSenseBluetoothInputReportID,
      bytes.count >= dualSenseBluetoothInputReportLength + 1
    {
      let report = Array(bytes.dropFirst())
      try validateBluetoothCRC(report: report)
      connectionMode = .bluetooth
      return Array(report.dropFirst(2).dropLast(4))
    }
    return []
  }

  private func validateBluetoothCRC(report: [UInt8]) throws {
    let expectedOffset = report.count - 4
    let expected =
      UInt32(report[expectedOffset]) | (UInt32(report[expectedOffset + 1]) << 8)
      | (UInt32(report[expectedOffset + 2]) << 16) | (UInt32(report[expectedOffset + 3]) << 24)
    guard dualSenseBluetoothCRC32(report: report) == expected else {
      throw DualSenseDriverError.invalidBluetoothCRC
    }
  }

  private func dualSenseBluetoothCRC32(report: [UInt8]) -> UInt32 {
    var crc = updateCRC32(0xFFFF_FFFF, byte: dualSenseInputCRC32Seed)
    for byte in report.dropLast(4) { crc = updateCRC32(crc, byte: byte) }
    return ~crc
  }

  private func dualSenseOutputCRC32(report: [UInt8]) -> UInt32 {
    var crc = updateCRC32(0xFFFF_FFFF, byte: dualSenseOutputCRC32Seed)
    for byte in report.dropLast(4) { crc = updateCRC32(crc, byte: byte) }
    return ~crc
  }

  private func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
    var crc = current ^ UInt32(byte)
    for _ in 0..<8 { if crc & 1 == 1 { crc = (crc >> 1) ^ 0xEDB8_8320 } else { crc >>= 1 } }
    return crc
  }

  private func normalizeHID(_ raw: UInt8) -> Float {
    let centered = Float(raw) - dualSenseAxisCenter
    let divisor = centered >= 0 ? dualSenseAxisPositiveMax : dualSenseAxisNegativeMax
    let normalized = centered / divisor
    return max(-1, min(1, normalized))
  }

  private func mapHat(_ hat: UInt8) -> HatDirection {
    switch hat {
    case 0: .north
    case 1: .northEast
    case 2: .east
    case 3: .southEast
    case 4: .south
    case 5: .southWest
    case 6: .west
    case 7: .northWest
    default: .neutral
    }
  }
}
