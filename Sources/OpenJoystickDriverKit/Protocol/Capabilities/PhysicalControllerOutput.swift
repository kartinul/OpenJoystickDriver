/// A physical rumble actuator that the active protocol implementation can address.
public enum PhysicalRumbleMotor: String, Codable, CaseIterable, Hashable, Sendable {
  case leftMain
  case rightMain
  case leftTrigger
  case rightTrigger
  case leftHaptic
  case rightHaptic
}

/// A physical lighting feature with a source-backed output implementation.
public enum PhysicalLightingFeature: String, Codable, CaseIterable, Hashable, Sendable {
  case playerIndicator
  case programmableColor
  case programmableBrightness
}

/// Generic player indicator selection for protocols with numbered controller LEDs.
public enum PhysicalPlayerIndicator: Int, Codable, CaseIterable, Hashable, Sendable {
  case off = 0
  case player1 = 1
  case player2 = 2
  case player3 = 3
  case player4 = 4
}

public enum PhysicalAdaptiveTrigger: String, Codable, CaseIterable, Hashable, Sendable {
  case left
  case right
}

public enum PhysicalAdaptiveTriggerEffectKind: String, Codable, CaseIterable, Hashable, Sendable {
  case off
  case resistance
}

/// A bounded DualSense-style trigger effect. Positions and strength are normalized to `0...1`.
public struct PhysicalAdaptiveTriggerEffect: Codable, Equatable, Hashable, Sendable {
  public let kind: PhysicalAdaptiveTriggerEffectKind
  public let startPosition: Double
  public let strength: Double

  public init(
    kind: PhysicalAdaptiveTriggerEffectKind,
    startPosition: Double = 0,
    strength: Double = 0
  ) {
    self.kind = kind
    self.startPosition = startPosition
    self.strength = strength
  }

  public static let off = Self(kind: .off)

  public func validate() throws {
    guard startPosition.isFinite, (0...1).contains(startPosition), strength.isFinite,
      (0...1).contains(strength)
    else { throw PhysicalAdaptiveTriggerEffectError.invalidValue }
    if kind == .off, startPosition != 0 || strength != 0 {
      throw PhysicalAdaptiveTriggerEffectError.invalidValue
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case startPosition
    case strength
  }
}

public enum PhysicalAdaptiveTriggerEffectError: Error, Equatable, Sendable { case invalidValue }

/// Physical output capabilities implemented by the active controller protocol.
public struct PhysicalControllerOutputCapabilities: Codable, Equatable, Hashable, Sendable {
  public let rumbleMotors: [PhysicalRumbleMotor]
  public let lightingFeatures: [PhysicalLightingFeature]
  /// Motors whose hardware accepts only off/on rather than variable intensity.
  public let binaryRumbleMotors: [PhysicalRumbleMotor]
  public let adaptiveTriggers: [PhysicalAdaptiveTrigger]
  public init(
    rumbleMotors: [PhysicalRumbleMotor] = [],
    lightingFeatures: [PhysicalLightingFeature] = [],
    binaryRumbleMotors: [PhysicalRumbleMotor] = [],
    adaptiveTriggers: [PhysicalAdaptiveTrigger] = []
  ) {
    self.rumbleMotors = Array(Set(rumbleMotors)).sorted { $0.rawValue < $1.rawValue }
    self.lightingFeatures = Array(Set(lightingFeatures)).sorted { $0.rawValue < $1.rawValue }
    let supportedMotors = Set(self.rumbleMotors)
    self.binaryRumbleMotors = Array(Set(binaryRumbleMotors).intersection(supportedMotors)).sorted {
      $0.rawValue < $1.rawValue
    }
    self.adaptiveTriggers = Array(Set(adaptiveTriggers)).sorted { $0.rawValue < $1.rawValue }
  }

  public static let none = Self()
  public static let dualMainRumble = Self(rumbleMotors: [.leftMain, .rightMain])

  public var supportsRumble: Bool { !rumbleMotors.isEmpty }
  public var supportsTriggerRumble: Bool {
    rumbleMotors.contains(.leftTrigger) || rumbleMotors.contains(.rightTrigger)
  }
  public var supportsPlayerIndicator: Bool { lightingFeatures.contains(.playerIndicator) }
  public var supportsProgrammableBrightness: Bool {
    lightingFeatures.contains(.programmableBrightness)
  }
  public var supportsAdaptiveTriggers: Bool { !adaptiveTriggers.isEmpty }

  private enum CodingKeys: String, CodingKey {
    case rumbleMotors
    case lightingFeatures
    case binaryRumbleMotors
    case adaptiveTriggers
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rumbleMotors: try values.decodeIfPresent([PhysicalRumbleMotor].self, forKey: .rumbleMotors)
        ?? [],
      lightingFeatures: try values.decodeIfPresent(
        [PhysicalLightingFeature].self,
        forKey: .lightingFeatures
      ) ?? [],
      binaryRumbleMotors: try values.decodeIfPresent(
        [PhysicalRumbleMotor].self,
        forKey: .binaryRumbleMotors
      ) ?? [],
      adaptiveTriggers: try values.decodeIfPresent(
        [PhysicalAdaptiveTrigger].self,
        forKey: .adaptiveTriggers
      ) ?? []
    )
  }
}

/// A raw HID feature-report read request sent through IOKit.
public struct PhysicalHIDFeatureReadRequest: Equatable, Sendable {
  public let reportID: UInt8
  public let length: Int

  public init(reportID: UInt8, length: Int) {
    self.reportID = reportID
    self.length = length
  }
}

/// A raw HID output report that can be sent through IOKit.
public struct PhysicalHIDOutputReport: Equatable, Sendable {
  public let reportID: UInt8
  public let bytes: [UInt8]

  public init(reportID: UInt8, bytes: [UInt8]) {
    self.reportID = reportID
    self.bytes = bytes
  }
}

public struct PhysicalUSBOutputPacket: Equatable, Sendable {
  public let endpoint: UInt8
  public let bytes: [UInt8]
  public let timeoutMilliseconds: UInt32

  public init(endpoint: UInt8, bytes: [UInt8], timeoutMilliseconds: UInt32) {
    self.endpoint = endpoint
    self.bytes = bytes
    self.timeoutMilliseconds = timeoutMilliseconds
  }
}

/// One write a driver asks its pipeline to perform; each write names its own destination.
public enum PhysicalOutputWrite: Equatable, Sendable {
  /// An interrupt OUT packet. A tolerated rejection (I/O error, timeout, missing or unsupported
  /// endpoint) is logged and does not fail the lifecycle step that produced the write.
  case usb(PhysicalUSBOutputPacket, toleratesRejection: Bool = false)
  /// A HID output report on the bound HID device.
  case hidOutput(PhysicalHIDOutputReport)
  /// A HID feature report on the bound HID device.
  case hidFeature(PhysicalHIDOutputReport)
}

/// Writes that carry one physical output command, sent in order at `intervalNanoseconds`
/// spacing; each write names its own destination.
public struct PhysicalOutputPlan: Equatable, Sendable {
  public let writes: [PhysicalOutputWrite]
  public let intervalNanoseconds: UInt64

  public init(writes: [PhysicalOutputWrite], intervalNanoseconds: UInt64 = 0) {
    self.writes = writes
    self.intervalNanoseconds = intervalNanoseconds
  }
}
