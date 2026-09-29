import Foundation

/// A physical-controller channel value owned by one remapping action while that action is active.
public enum RemappingPhysicalOutput: Codable, Equatable, Hashable, Sendable {
  case rumble(motor: PhysicalRumbleMotor, intensity: Double)
  case playerIndicator(PhysicalPlayerIndicator)
  case color(ControllerColor)
  case brightness(Double)
  case adaptiveTrigger(PhysicalAdaptiveTrigger, PhysicalAdaptiveTriggerEffect)

  public func validate() throws {
    switch self {
    case .rumble(_, let intensity), .brightness(let intensity):
      guard intensity.isFinite, (0...1).contains(intensity) else {
        throw RemappingPhysicalOutputError.invalidValue
      }
    case .adaptiveTrigger(_, let effect):
      do { try effect.validate() } catch { throw RemappingPhysicalOutputError.invalidValue }
    case .playerIndicator, .color: break
    }
  }

  private enum Kind: String, Codable {
    case rumble
    case playerIndicator = "player_indicator"
    case color
    case brightness
    case adaptiveTrigger = "adaptive_trigger"

    var fields: [CodingKeys] {
      switch self {
      case .rumble: [.type, .motor, .intensity]
      case .playerIndicator: [.type, .indicator]
      case .color: [.type, .red, .green, .blue]
      case .brightness: [.type, .intensity]
      case .adaptiveTrigger: [.type, .trigger, .effect]
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type, motor, intensity, indicator, red, green, blue, trigger, effect
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(Kind.self, forKey: .type)
    try values.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .rumble:
      self = .rumble(
        motor: try values.decode(PhysicalRumbleMotor.self, forKey: .motor),
        intensity: try values.decode(Double.self, forKey: .intensity)
      )
    case .playerIndicator:
      self = .playerIndicator(try values.decode(PhysicalPlayerIndicator.self, forKey: .indicator))
    case .color:
      self = .color(
        ControllerColor(
          red: try values.decode(UInt8.self, forKey: .red),
          green: try values.decode(UInt8.self, forKey: .green),
          blue: try values.decode(UInt8.self, forKey: .blue)
        )
      )
    case .brightness: self = .brightness(try values.decode(Double.self, forKey: .intensity))
    case .adaptiveTrigger:
      self = .adaptiveTrigger(
        try values.decode(PhysicalAdaptiveTrigger.self, forKey: .trigger),
        try values.decode(PhysicalAdaptiveTriggerEffect.self, forKey: .effect)
      )
    }
    try validate()
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .rumble(let motor, let intensity):
      try values.encode(Kind.rumble, forKey: .type)
      try values.encode(motor, forKey: .motor)
      try values.encode(intensity, forKey: .intensity)
    case .playerIndicator(let indicator):
      try values.encode(Kind.playerIndicator, forKey: .type)
      try values.encode(indicator, forKey: .indicator)
    case .color(let color):
      try values.encode(Kind.color, forKey: .type)
      try values.encode(color.red, forKey: .red)
      try values.encode(color.green, forKey: .green)
      try values.encode(color.blue, forKey: .blue)
    case .brightness(let intensity):
      try values.encode(Kind.brightness, forKey: .type)
      try values.encode(intensity, forKey: .intensity)
    case .adaptiveTrigger(let trigger, let effect):
      try values.encode(Kind.adaptiveTrigger, forKey: .type)
      try values.encode(trigger, forKey: .trigger)
      try values.encode(effect, forKey: .effect)
    }
  }
}

public enum RemappingPhysicalOutputError: Error, Equatable, Sendable { case invalidValue }
