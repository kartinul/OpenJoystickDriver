import Foundation

/// Original Xbox XID input report length used by Linux `xpad_process_packet`.
private let xidInputReportLength = 20
private let xidTriggerMax: Float = 255
private let xidStickMax = Float(Int16.max)

/// Driver for original Xbox XID pads (`xpad` `XTYPE_XBOX`).
///
/// XID is vendor USB, not HID. Layout follows Linux `xpad_process_packet`:
/// digital dpad/start/back/sticks in byte 2, analog A/B/X/Y in bytes 4–7,
/// analog black/white shoulders in bytes 8–9, analog triggers in bytes 10–11,
/// and Int16 LE sticks at bytes 12–19. Any nonzero analog face or shoulder
/// value is pressed, matching `input_report_key` in `xpad.c`.
public final class XIDDriver: PhysicalProtocolDriver {
  private let outEndpoint: UInt8
  private var state = ControllerState.neutral

  public init(outEndpoint: UInt8 = 0x02) { self.outEndpoint = outEndpoint }

  /// A new transport session starts from neutral input.
  public func resetProtocolState() { state = .neutral }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: ControlID.xboxLayout)
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities { .dualMainRumble }
  public var defaultColor: ControllerColor? { nil }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let intensities: RumbleIntensities
    switch command {
    case .setRumble(let requested, _): intensities = requested
    case .stopRumble: intensities = .off
    default: throw .unsupportedCapability(command.capability)
    }
    let leftValue = UInt16(intensities.leftMain.byte) * 257
    let rightValue = UInt16(intensities.rightMain.byte) * 257
    let packet = PhysicalUSBOutputPacket(
      endpoint: outEndpoint,
      bytes: [
        0x00, 0x06, UInt8(leftValue >> 8), UInt8(leftValue & 0xFF), UInt8(rightValue >> 8),
        UInt8(rightValue & 0xFF),
      ],
      timeoutMilliseconds: 2_000
    )
    return PhysicalOutputPlan(writes: [.usb(packet)])
  }

  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    guard data.count >= xidInputReportLength else { return nil }
    let bytes = Array(data)
    let digital = bytes[2]
    let lsx = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[14]) | (UInt16(bytes[15]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[16]) | (UInt16(bytes[17]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[18]) | (UInt16(bytes[19]) << 8))

    var next = state
    next.hat = mapDpad(digital & 0x0F)
    for (bit, control) in [
      (4, ControlID.menu), (5, .view), (6, .leftStickClick), (7, .rightStickClick),
    ] { next.set(control, pressed: digital & (1 << bit) != 0) }
    // Any nonzero analog face or shoulder value is pressed.
    for (offset, control) in [
      (4, ControlID.faceSouth), (5, .faceEast), (6, .faceWest), (7, .faceNorth), (8, .leftShoulder),
      (9, .rightShoulder),
    ] { next.set(control, pressed: bytes[offset] != 0) }
    next.leftTrigger = UnipolarValue(normalized: Float(bytes[10]) / xidTriggerMax)
    next.rightTrigger = UnipolarValue(normalized: Float(bytes[11]) / xidTriggerMax)
    next.leftStick = StickPosition(x: normalizeStick(lsx), yDown: -normalizeStick(lsy))
    next.rightStick = StickPosition(x: normalizeStick(rsx), yDown: -normalizeStick(rsy))
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  private func normalizeStick(_ raw: Int16) -> Float {
    if raw == Int16.min { return -1.0 }
    return Float(raw) / xidStickMax
  }

  private func mapDpad(_ value: UInt8) -> HatDirection {
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast
    case 10: .southEast
    case 6: .southWest
    case 5: .northWest
    default: .neutral
    }
  }
}
