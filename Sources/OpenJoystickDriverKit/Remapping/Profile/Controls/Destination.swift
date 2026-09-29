import Foundation

/// The system-input destination of a binding.
public enum RemappingDestination: Codable, Equatable, Hashable, Sendable {
  case gamepadButton(RemappingButton)
  case gamepadDpad(RemappingDpadDirection)
  case gamepadAxis(RemappingAxis)
  case keyboard(key: RemappingKeyboardKey, modifiers: Set<RemappingKeyModifier>)
  case mouseButton(RemappingMouseButton)
  case mouseMovement(RemappingPointerAxis)
  case scroll(RemappingPointerAxis)
  case physical(RemappingPhysicalOutput)

  public var acceptsTurbo: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad: true
    case .mouseMovement, .scroll, .gamepadAxis, .physical: false
    }
  }

  public var isContinuous: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .physical: false
    case .mouseMovement, .scroll, .gamepadAxis: true
    }
  }

  private enum Kind: String, Codable {
    case keyboard
    case gamepadButton = "gamepad_button"
    case gamepadDpad = "gamepad_dpad"
    case gamepadAxis = "gamepad_axis"
    case mouseButton = "mouse_button"
    case mouseMovement = "mouse_movement"
    case scroll
    case physical

    var fields: [CodingKeys] {
      switch self {
      case .keyboard: [.type, .key, .modifiers]
      case .gamepadButton, .mouseButton: [.type, .button]
      case .gamepadDpad: [.type, .direction]
      case .gamepadAxis, .mouseMovement, .scroll: [.type, .axis]
      case .physical: [.type, .physical]
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case key
    case modifiers
    case button
    case axis
    case direction
    case physical
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    try container.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .gamepadAxis: self = .gamepadAxis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .gamepadDpad:
      self = .gamepadDpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .gamepadButton:
      self = .gamepadButton(try container.decode(RemappingButton.self, forKey: .button))
    case .keyboard:
      let modifiers = try container.decode([RemappingKeyModifier].self, forKey: .modifiers)
      self = .keyboard(
        key: try container.decode(RemappingKeyboardKey.self, forKey: .key),
        modifiers: Set(modifiers)
      )
    case .mouseButton:
      self = .mouseButton(try container.decode(RemappingMouseButton.self, forKey: .button))
    case .mouseMovement:
      self = .mouseMovement(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .scroll: self = .scroll(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .physical:
      self = .physical(try container.decode(RemappingPhysicalOutput.self, forKey: .physical))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .gamepadAxis(let axis):
      try container.encode(Kind.gamepadAxis, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .gamepadDpad(let direction):
      try container.encode(Kind.gamepadDpad, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .gamepadButton(let button):
      try container.encode(Kind.gamepadButton, forKey: .type)
      try container.encode(button, forKey: .button)
    case .keyboard(let key, let modifiers):
      try container.encode(Kind.keyboard, forKey: .type)
      try container.encode(key, forKey: .key)
      try container.encode(modifiers.sorted { $0.rawValue < $1.rawValue }, forKey: .modifiers)
    case .mouseButton(let button):
      try container.encode(Kind.mouseButton, forKey: .type)
      try container.encode(button, forKey: .button)
    case .mouseMovement(let axis):
      try container.encode(Kind.mouseMovement, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .scroll(let axis):
      try container.encode(Kind.scroll, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .physical(let output):
      try container.encode(Kind.physical, forKey: .type)
      try container.encode(output, forKey: .physical)
    }
  }
}
