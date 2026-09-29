import Foundation

/// Parser for controllers that expose a fixed byte-offset HID report layout
/// without a usable HID descriptor.
///
/// This parser deliberately does **not** conform to ``HIDElementValueParser``.
/// OJD's CoreHID backend resolves parsers that conform to that protocol to
/// descriptor-decoded element updates and discards raw reports
/// (`CoreHIDInputSubscriptionPlan.resolve`). By staying raw-report-only this
/// parser receives every input report through ``parse(data:)``.
///
/// Report layout (byte 0 = report ID, minimum 22 bytes):
/// ```
///   byte 0   : report ID
///   byte 1   : meta bitmask
///              bit 0  back (Select)
///              bit 1  start
///              bit 2  leftStick (L3)
///              bit 3  rightStick (R3)
///   byte 2   : unused
///   byte 3   : left stick X  (0-255, center 127)
///   byte 4   : left stick Y  (0-255, center 127)
///   byte 5   : right stick X (0-255, center 127)
///   byte 6   : right stick Y (0-255, center 127)
///   byte 7   : dpad right    (bit 7)
///   byte 8   : dpad left     (bit 7)
///   byte 9   : dpad up       (bit 7)
///   byte 10  : dpad down     (bit 7)
///   byte 11  : Y              (bit 7)
///   byte 12  : B              (bit 7)
///   byte 13  : A              (bit 7)
///   byte 14  : X              (bit 7)
///   byte 15  : left bumper    (bit 7)
///   byte 16  : right bumper   (bit 7)
///   byte 17  : left trigger   (0-255, 0 = released)
///   byte 18  : right trigger  (0-255, 0 = released)
///   byte 19  : noise (ignored)
///   byte 20  : unused
///   byte 21  : noise (ignored)
/// ```
public final class GenericByteLayoutParser: InputParser {
  private static let minimumReportLength = 22
  /// Half the axis travel. Center is 127.5 so byte 0 maps to -1 and byte 255 to +1.
  private static let stickCenter: Float = 127.5
  private static let stickSpan: Float = 127.5
  private static let triggerMax: Float = 255
  private static let deadzone: Float = 0.08

  private let stateLock = NSLock()
  private var previousMeta: UInt8 = 0
  private var previousDpad: UInt8 = 0
  private var previousY = false
  private var previousB = false
  private var previousA = false
  private var previousX = false
  private var previousLeftBumper = false
  private var previousRightBumper = false
  private var previousLeftTrigger: UInt8 = 0
  private var previousRightTrigger: UInt8 = 0
  private var previousLeftX: UInt8 = 127
  private var previousLeftY: UInt8 = 128
  private var previousRightX: UInt8 = 127
  private var previousRightY: UInt8 = 128

  /// Creates a new GenericByteLayoutParser.
  public init() {}

  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = [UInt8](data)
    return stateLock.withLock {
      guard bytes.count >= Self.minimumReportLength else { return [] }

      var events: [ControllerEvent] = []

      // Meta buttons (byte 1): back, start, L3, R3
      let meta = bytes[1]
      events += diffButtons(
        prev: previousMeta,
        curr: meta,
        mapping: [(0x01, .back), (0x02, .start), (0x04, .leftStick), (0x08, .rightStick)]
      )

      // Face buttons (bytes 11-14): Y, B, A, X. Each occupies its own byte, so
      // they are diffed per byte rather than packed into one bitmask.
      events += faceButtonEvents(bytes)

      // Bumpers (bytes 15-16): LB, RB. One byte each, same reasoning.
      events += bumperButtonEvents(bytes)

      // Dpad (bytes 7-10): right, left, up, down. Each direction owns a byte
      // with bit 7 active, so the four are combined into a direction index
      // rather than a bitmask.
      let dpad: UInt8 =
        (bytes[7] & 0x80 != 0 ? 1 : 0) | (bytes[8] & 0x80 != 0 ? 2 : 0)
        | (bytes[9] & 0x80 != 0 ? 4 : 0) | (bytes[10] & 0x80 != 0 ? 8 : 0)
      if dpad != previousDpad { events.append(.dpadChanged(Self.dpadDirection(dpad))) }

      // Triggers (bytes 17-18)
      let lt = bytes[17]
      let rt = bytes[18]
      if lt != previousLeftTrigger { events.append(.leftTriggerChanged(Self.normalizeTrigger(lt))) }
      if rt != previousRightTrigger {
        events.append(.rightTriggerChanged(Self.normalizeTrigger(rt)))
      }

      // Sticks (bytes 3-6). Raw device orientation is reported as-is: the Y
      // axis sign is a user preference, not a device fact, so inversion is
      // left to profile stick tuning (`--stick-invert-y`) and per-binding
      // `--invert`. Events are gated on the normalized value so rest noise
      // inside the deadzone reports nothing.
      let lsx = bytes[3]
      let lsy = bytes[4]
      let rsx = bytes[5]
      let rsy = bytes[6]
      let leftX = Self.normalizeStick(lsx)
      let leftY = Self.normalizeStick(lsy)
      let rightX = Self.normalizeStick(rsx)
      let rightY = Self.normalizeStick(rsy)
      let previousLeftXValue = Self.normalizeStick(previousLeftX)
      let previousLeftYValue = Self.normalizeStick(previousLeftY)
      let previousRightXValue = Self.normalizeStick(previousRightX)
      let previousRightYValue = Self.normalizeStick(previousRightY)
      if leftX != previousLeftXValue || leftY != previousLeftYValue {
        events.append(.leftStickChanged(x: leftX, y: leftY))
      }
      if rightX != previousRightXValue || rightY != previousRightYValue {
        events.append(.rightStickChanged(x: rightX, y: rightY))
      }

      previousMeta = meta
      previousDpad = dpad
      previousLeftTrigger = lt
      previousRightTrigger = rt
      previousLeftX = lsx
      previousLeftY = lsy
      previousRightX = rsx
      previousRightY = rsy

      return events
    }
  }

  // MARK: - Per-byte button diffing

  /// Diffs the four face-button bytes. Each button has a dedicated byte with the
  /// active state in bit 7, so buttons cannot share a packed bitmask.
  private func faceButtonEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    events += diff(previous: previousY, current: bytes[11] & 0x80 != 0, button: .y)
    events += diff(previous: previousB, current: bytes[12] & 0x80 != 0, button: .b)
    events += diff(previous: previousA, current: bytes[13] & 0x80 != 0, button: .a)
    events += diff(previous: previousX, current: bytes[14] & 0x80 != 0, button: .x)
    previousY = bytes[11] & 0x80 != 0
    previousB = bytes[12] & 0x80 != 0
    previousA = bytes[13] & 0x80 != 0
    previousX = bytes[14] & 0x80 != 0
    return events
  }

  /// Diffs the two bumper bytes. One byte each, bit 7 active.
  private func bumperButtonEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    events += diff(
      previous: previousLeftBumper,
      current: bytes[15] & 0x80 != 0,
      button: .leftBumper
    )
    events += diff(
      previous: previousRightBumper,
      current: bytes[16] & 0x80 != 0,
      button: .rightBumper
    )
    previousLeftBumper = bytes[15] & 0x80 != 0
    previousRightBumper = bytes[16] & 0x80 != 0
    return events
  }

  private func diff(previous: Bool, current: Bool, button: Button) -> [ControllerEvent] {
    guard previous != current else { return [] }
    return [current ? .buttonPressed(button) : .buttonReleased(button)]
  }

  // MARK: - Normalization

  private static func normalizeStick(_ raw: UInt8) -> Float {
    let normalized = (Float(raw) - stickCenter) / stickSpan
    let clamped = max(-1, min(1, normalized))
    return abs(clamped) < deadzone ? 0 : clamped
  }

  private static func normalizeTrigger(_ raw: UInt8) -> Float {
    min(1, max(0, Float(raw) / triggerMax))
  }

  /// Maps a combined dpad index to a direction.
  /// Bits: 1 = right, 2 = left, 4 = up, 8 = down.
  private static func dpadDirection(_ value: UInt8) -> DpadDirection {
    switch value {
    case 0: .neutral
    case 4: .north
    case 4 | 1: .northEast
    case 1: .east
    case 8 | 1: .southEast
    case 8: .south
    case 8 | 2: .southWest
    case 2: .west
    case 4 | 2: .northWest
    default: .neutral
    }
  }
}
