import Foundation

extension BipolarValue {
  /// Quantizes a normalized `-1...1` value by truncation toward zero, the quantization the virtual
  /// output applies to the same value. Values outside the range clamp; non-finite is center.
  public init(normalized value: Float) {
    guard value.isFinite else {
      self = .center
      return
    }
    self.init(Int16(Swift.min(Swift.max(value, -1), 1) * Float(Int16.max)))
  }

  /// The value as a `-1...1` float, for consumers that compute in floating point.
  public var normalized: Float { Float(rawValue) / Float(Int16.max) }
}

extension UnipolarValue {
  /// Quantizes a normalized `0...1` value by truncation toward zero. Values outside the range
  /// clamp; a non-finite value is released.
  public init(normalized value: Float) {
    guard value.isFinite else {
      self = .min
      return
    }
    self.init(UInt16(Swift.min(Swift.max(value, 0), 1) * Float(UInt16.max)))
  }

  /// The value as a `0...1` float, for consumers that compute in floating point.
  public var normalized: Float { Float(rawValue) / Float(UInt16.max) }
}

/// One analog stick: positive X is right, positive Y is up.
public struct StickPosition: Hashable, Codable, Sendable {
  public static let center = Self(x: .center, y: .center)

  public var x: BipolarValue
  public var y: BipolarValue

  public init(x: BipolarValue, y: BipolarValue) {
    self.x = x
    self.y = y
  }

  /// Quantizes a driver's normalized `-1...1` axes; `yDown` is positive toward the player, the
  /// frame most reports use, and is negated here, once, into the canonical Y-up frame.
  init(x: Float, yDown: Float) {
    self.init(x: BipolarValue(normalized: x), y: BipolarValue(normalized: -yDown))
  }
}

/// The complete normalized state of one logical controller.
///
/// A driver decodes every accepted input report into a full snapshot: a control absent from
/// `pressed` is released. Raw report bytes never appear here.
public struct ControllerState: Equatable, Codable, Sendable {
  public static let neutral = Self()

  /// Digital controls currently held. The hat is not listed here.
  public var pressed: Set<ControlID>
  public var hat: HatDirection
  public var leftStick: StickPosition
  public var rightStick: StickPosition
  public var leftTrigger: UnipolarValue
  public var rightTrigger: UnipolarValue
  /// Latest complete contact frame of each touch surface the controller reports.
  public var touch: [ControllerTouchSample]
  /// Link and power state, stamped by the pipeline; nil where no binding describes the link.
  public var connection: ControllerConnectionState?

  public init(
    pressed: Set<ControlID> = [],
    hat: HatDirection = .neutral,
    leftStick: StickPosition = .center,
    rightStick: StickPosition = .center,
    leftTrigger: UnipolarValue = .min,
    rightTrigger: UnipolarValue = .min,
    touch: [ControllerTouchSample] = [],
    connection: ControllerConnectionState? = nil
  ) {
    self.pressed = pressed
    self.hat = hat
    self.leftStick = leftStick
    self.rightStick = rightStick
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.touch = touch
    self.connection = connection
  }

  /// Presses or releases one digital control.
  mutating func set(_ control: ControlID, pressed isPressed: Bool) {
    if isPressed { pressed.insert(control) } else { pressed.remove(control) }
  }

  /// Keeps the latest frame of each surface in `frames`, in wire order.
  public mutating func recordTouch(_ frames: [ControllerTouchSample]) {
    for frame in frames {
      touch.removeAll { $0.surface == frame.surface }
      touch.append(frame)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case pressed, hat, leftStick, rightStick, leftTrigger, rightTrigger, touch, connection
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    pressed = Set(try values.decode([ControlID].self, forKey: .pressed))
    hat = try values.decode(HatDirection.self, forKey: .hat)
    leftStick = try values.decode(StickPosition.self, forKey: .leftStick)
    rightStick = try values.decode(StickPosition.self, forKey: .rightStick)
    leftTrigger = try values.decode(UnipolarValue.self, forKey: .leftTrigger)
    rightTrigger = try values.decode(UnipolarValue.self, forKey: .rightTrigger)
    touch = try values.decode([ControllerTouchSample].self, forKey: .touch)
    connection = try values.decodeIfPresent(ControllerConnectionState.self, forKey: .connection)
  }

  /// Encodes `pressed` in `ControlID` declaration order, so equal states encode identically.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(ControlID.allCases.filter(pressed.contains), forKey: .pressed)
    try values.encode(hat, forKey: .hat)
    try values.encode(leftStick, forKey: .leftStick)
    try values.encode(rightStick, forKey: .rightStick)
    try values.encode(leftTrigger, forKey: .leftTrigger)
    try values.encode(rightTrigger, forKey: .rightTrigger)
    try values.encode(touch, forKey: .touch)
    try values.encodeIfPresent(connection, forKey: .connection)
  }
}

/// One accepted input report: the controller's full state after it, plus the ordered samples the
/// report carried.
public struct ControllerEvent: Equatable, Sendable {
  /// Host receipt time of the report.
  public let timestamp: MonotonicTimestamp
  public let state: ControllerState
  /// Every motion sample of the report in wire order, including repeated readings.
  public let motion: [ControllerMotionSample]
  /// Every touch frame of the report in wire order, including historical frames.
  public let touchFrames: [ControllerTouchSample]
  /// False when the report repeats a stale device sample; such a report must not refresh input
  /// liveness.
  public let isFresh: Bool

  public init(
    timestamp: MonotonicTimestamp,
    state: ControllerState,
    motion: [ControllerMotionSample] = [],
    touchFrames: [ControllerTouchSample] = [],
    isFresh: Bool = true
  ) {
    self.timestamp = timestamp
    self.state = state
    self.motion = motion
    self.touchFrames = touchFrames
    self.isFresh = isFresh
  }
}
