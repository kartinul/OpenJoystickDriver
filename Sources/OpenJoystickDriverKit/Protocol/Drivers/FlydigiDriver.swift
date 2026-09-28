import Foundation

private let flydigiInputReportID: UInt8 = 0x01
private let flydigiReportLength = 15
private let flydigiAxisMagnitude: Float = 127
private let flydigiTriggerMax: Float = 255
private let flydigiHatNeutral: UInt8 = 0

/// Driver for Flydigi Vader-family controllers on Bluetooth Low Energy.
///
/// The report declares GamePad usage and standard Generic Desktop axes, but
/// packs the right stick into Z/Rz and the analog triggers into the Simulation
/// page, so the descriptor-driven fallback maps neither correctly. Button
/// usages are also non-contiguous, which shifts every index after the first
/// gap. This driver reads the observed 15-byte layout by offset instead.
public final class FlydigiDriver: PhysicalProtocolDriver {

  private enum ReportOffset {
    static let leftStickX: Int = 1
    static let leftStickY: Int = 2
    static let rightStickX: Int = 3
    static let rightStickY: Int = 4
    /// Low nibble is the D-pad hat; high nibble carries the face buttons.
    static let hatAndFace: Int = 9
    static let shoulders: Int = 10
    static let extras: Int = 11
    static let system: Int = 12
    static let leftTrigger: Int = 13
    static let rightTrigger: Int = 14
  }

  private enum FaceMask {
    static let a: UInt8 = 0x10
    static let b: UInt8 = 0x20
    static let x: UInt8 = 0x40
    static let y: UInt8 = 0x80
  }

  private enum ShoulderMask {
    static let leftBumper: UInt8 = 0x01
    static let rightBumper: UInt8 = 0x02
    static let leftTrigger: UInt8 = 0x04
    static let rightTrigger: UInt8 = 0x08
    static let back: UInt8 = 0x10
    static let start: UInt8 = 0x20
    static let leftStick: UInt8 = 0x40
    static let rightStick: UInt8 = 0x80
  }

  private enum SystemMask { static let guide: UInt8 = 0x80 }

  private var state = ControllerState.neutral
  private let stateLock = NSLock()

  /// Creates a new FlydigiDriver.
  public init() {}

  /// A new transport session starts from neutral input.
  public func resetProtocolState() { stateLock.withLock { state = .neutral } }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }
  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }
  public var defaultColor: (red: UInt8, green: UInt8, blue: UInt8)? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: ControlID.xboxLayout.union([.guide, .leftTriggerButton, .rightTriggerButton])
    )
  }

  /// Decodes one Flydigi input report into the full controller state.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard bytes.count == flydigiReportLength, bytes.first == flydigiInputReportID else {
      return nil
    }

    return stateLock.withLock {
      var next = state
      let hatAndFace = bytes[ReportOffset.hatAndFace]
      let shoulders = bytes[ReportOffset.shoulders]
      for (mask, control) in [
        (FaceMask.a, ControlID.faceSouth), (FaceMask.b, .faceEast), (FaceMask.x, .faceWest),
        (FaceMask.y, .faceNorth),
      ] { next.set(control, pressed: hatAndFace & mask != 0) }
      next.hat = Self.direction(for: hatAndFace & 0x0F)
      // The shoulder byte's trigger bits are the protocol's digital trigger signal; the analog
      // bytes alone drive the trigger position.
      for (mask, control) in [
        (ShoulderMask.leftBumper, ControlID.leftShoulder),
        (ShoulderMask.rightBumper, .rightShoulder), (ShoulderMask.leftTrigger, .leftTriggerButton),
        (ShoulderMask.rightTrigger, .rightTriggerButton), (ShoulderMask.back, .view),
        (ShoulderMask.start, .menu), (ShoulderMask.leftStick, .leftStickClick),
        (ShoulderMask.rightStick, .rightStickClick),
      ] { next.set(control, pressed: shoulders & mask != 0) }
      next.set(.guide, pressed: bytes[ReportOffset.system] & SystemMask.guide != 0)
      next.leftTrigger = UnipolarValue(
        normalized: Float(bytes[ReportOffset.leftTrigger]) / flydigiTriggerMax
      )
      next.rightTrigger = UnipolarValue(
        normalized: Float(bytes[ReportOffset.rightTrigger]) / flydigiTriggerMax
      )
      next.leftStick = StickPosition(
        x: Self.axis(bytes[ReportOffset.leftStickX]),
        yDown: Self.axis(bytes[ReportOffset.leftStickY])
      )
      next.rightStick = StickPosition(
        x: Self.axis(bytes[ReportOffset.rightStickX]),
        yDown: Self.axis(bytes[ReportOffset.rightStickY])
      )
      state = next
      return ControllerEvent(timestamp: receivedAt, state: next)
    }
  }

  /// Converts the 4-bit hat in the low nibble, 1 = up and increasing clockwise, to a compass
  /// direction; anything outside 1...8 is neutral.
  private static func direction(for hat: UInt8) -> HatDirection {
    switch hat {
    case 1: return .north
    case 2: return .northEast
    case 3: return .east
    case 4: return .southEast
    case 5: return .south
    case 6: return .southWest
    case 7: return .west
    case 8: return .northWest
    default: return .neutral
    }
  }

  /// Converts one signed axis byte to -1...1, where the hardware reports
  /// negative for up and left.
  static func axis(_ raw: UInt8) -> Float {
    max(-1, min(1, Float(Int8(bitPattern: raw)) / flydigiAxisMagnitude))
  }
}
