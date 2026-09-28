/// Normalized controls and sample formats a parser can emit, not a claim of hardware validation.
/// Motion means gyroscope and accelerometer samples in SI units and the canonical controller frame.
public struct ControllerCapabilities: Codable, Hashable, Sendable {
  public let controls: Set<ControlID>
  /// Maximum contacts in one decoded touch frame. Zero means touch decoding is unavailable.
  public let touchContactCount: UInt8
  public let motion: Bool

  public init(controls: Set<ControlID>, touchContactCount: UInt8 = 0, motion: Bool = false) {
    self.controls = controls
    self.touchContactCount = touchContactCount
    self.motion = motion
  }

  /// Surface identities emitted by touch samples: one per trackpad, otherwise one primary pad.
  public var touchSurfaces: [ControllerTouchSurface] {
    guard touchContactCount > 0 else { return [] }
    let trackpads = [
      (ControlID.leftTrackpadTouch, ControllerTouchSurface.left), (.rightTrackpadTouch, .right),
    ].filter { controls.contains($0.0) }.map(\.1)
    return trackpads.isEmpty ? [.primary] : trackpads
  }

  public func intersecting(_ other: Self) -> Self {
    Self(
      controls: controls.intersection(other.controls),
      touchContactCount: min(touchContactCount, other.touchContactCount),
      motion: motion && other.motion
    )
  }

  public func union(_ other: Self) -> Self {
    Self(
      controls: controls.union(other.controls),
      touchContactCount: max(touchContactCount, other.touchContactCount),
      motion: motion || other.motion
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(ControlID.allCases.filter(controls.contains), forKey: .controls)
    try container.encode(touchContactCount, forKey: .touchContactCount)
    try container.encode(motion, forKey: .motion)
  }
}

/// Evidenced capability corrections a catalog row applies to its parser's declared defaults.
public struct ControllerCapabilityDelta: Equatable, Sendable {
  public static let none = Self(absentControls: [], presentControls: [], rumbleAbsent: false)

  /// Declared controls this model does not have.
  public let absentControls: Set<ControlID>
  /// Controls this model adds to its family defaults; the driver emits them only when selected.
  public let presentControls: Set<ControlID>
  /// The model has no rumble channel.
  public let rumbleAbsent: Bool

  public init(absentControls: Set<ControlID>, presentControls: Set<ControlID>, rumbleAbsent: Bool) {
    self.absentControls = absentControls
    self.presentControls = presentControls
    self.rumbleAbsent = rumbleAbsent
  }
}
