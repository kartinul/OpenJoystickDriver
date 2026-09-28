/// The left axis pair alternates between stick and pad when both are active.
/// The pads have no touch clock: frames carry the report's receipt-anchored motion time.
struct SteamTouchSamples {
  private enum Report {
    static let buttonByte = 10
    static let leftPadMask: UInt8 = 0x08
    static let interleavedLeftMask: UInt8 = 0x80
    static let rightPadMask: UInt8 = 0x10
    static let leftXOffset = 16
    static let leftYOffset = 18
    static let rightXOffset = 20
    static let rightYOffset = 22
  }

  /// Signed 16-bit pad coordinates; raw Y grows upward, as the stick Y that shares the right-pad
  /// fields (`SteamControllerDriver.decodeControllerState` negates it to Y-down).
  static let trackpad = ControllerTouchGeometry(
    originX: -32_768,
    originY: -32_768,
    width: 65_536,
    height: 65_536,
    rawYIncreasesUpward: true
  )

  private var leftX: Int32 = 0
  private var leftY: Int32 = 0

  mutating func decode(_ bytes: [UInt8], timestamp: MonotonicTimestamp) -> [ControllerTouchSample] {
    let padPacket = bytes[Report.buttonByte] & Report.leftPadMask != 0
    let interleaved = bytes[Report.buttonByte] & Report.interleavedLeftMask != 0
    if padPacket {
      leftX = signed16(bytes, at: Report.leftXOffset)
      leftY = signed16(bytes, at: Report.leftYOffset)
    } else if !interleaved {
      leftX = 0
      leftY = 0
    }
    return [
      frame(.left, active: padPacket || interleaved, x: leftX, y: leftY, timestamp: timestamp),
      frame(
        .right,
        active: bytes[Report.buttonByte] & Report.rightPadMask != 0,
        x: signed16(bytes, at: Report.rightXOffset),
        y: signed16(bytes, at: Report.rightYOffset),
        timestamp: timestamp
      ),
    ]
  }

  private func frame(
    _ surface: ControllerTouchSurface,
    active: Bool,
    x: Int32,
    y: Int32,
    timestamp: MonotonicTimestamp
  ) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: surface,
      timestamp: timestamp,
      contacts: [Self.trackpad.contact(slot: 0, isActive: active, rawX: x, rawY: y)]
    )
  }

  private func signed16(_ bytes: [UInt8], at offset: Int) -> Int32 {
    Int32(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
  }
}
