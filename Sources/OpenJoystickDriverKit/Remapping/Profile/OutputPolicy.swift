import Foundation

/// Selects the virtual contribution of controls that have no active mapping.
public enum RemappingVirtualGamepadPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  /// Synthesizes system input without creating a virtual gamepad.
  case disabled
  /// Emits only destinations explicitly assigned by the profile.
  case mapped
  /// Also forwards controls that the active mapping does not consume.
  case passthrough
}

/// Physical ownership required before the profile may emit input.
public enum RemappingPhysicalInputPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  /// Allows system-input mappings while native physical input remains visible.
  case shared
  /// Requires confirmed exclusive physical ownership.
  case exclusive
}

/// Declares output routing and physical isolation independently of individual bindings.
public struct RemappingOutputPolicy: Codable, Equatable, Hashable, Sendable {
  public let virtualGamepad: RemappingVirtualGamepadPolicy
  public let physicalInput: RemappingPhysicalInputPolicy

  public init(
    virtualGamepad: RemappingVirtualGamepadPolicy = .disabled,
    physicalInput: RemappingPhysicalInputPolicy = .shared
  ) {
    self.virtualGamepad = virtualGamepad
    self.physicalInput = physicalInput
  }

  /// Preserves the behavior of profiles written before virtual remapping support.
  public static let systemInput = Self()

  /// Virtual remapping requires isolation even when shared system input was requested.
  public var requiresExclusiveInput: Bool {
    physicalInput == .exclusive || virtualGamepad != .disabled
  }

  private enum CodingKeys: String, CodingKey {
    case virtualGamepad
    case physicalInput
  }
}

extension RemappingProfile {
  /// Whether mapped-only output leaves every controller control without a virtual destination.
  public var suppressesAllControllerInput: Bool {
    guard outputPolicy.virtualGamepad == .mapped else { return false }
    if gyroOutput.mode == .leftStick || gyroOutput.mode == .rightStick
      || motionTuning.steering != nil
      || layers.contains(where: { $0.motionTuning?.steering != nil })
      || stickMappings.contains(where: { $0.mode == .steering || $0.passthrough })
      || triggerMappings.contains(where: \.passthrough)
      || touchMappings.contains(where: { $0.mode != .pointer })
    {
      return false
    }
    return !Self.containsVirtualGamepadOutput(
      bindings: bindings,
      chords: chords,
      sequences: sequences
    )
      && !layers.contains {
        Self.containsVirtualGamepadOutput(
          bindings: $0.bindings,
          chords: $0.chords,
          sequences: $0.sequences
        )
      }
  }

  /// Restores unmodified virtual controller input without changing profile content.
  public func restoringDefaultInput() -> Self {
    replacingInputConfiguration(
      outputPolicy: RemappingOutputPolicy(
        virtualGamepad: .passthrough,
        physicalInput: outputPolicy.physicalInput
      )
    )
  }

  /// Removes all input processing while retaining profile identity and physical-output settings.
  public func clearingAllInput() -> Self {
    replacingInputConfiguration(
      outputPolicy: RemappingOutputPolicy(
        virtualGamepad: .mapped,
        physicalInput: outputPolicy.physicalInput
      ),
      motionTuning: .default,
      gyroOutput: .default,
      stickMappings: [],
      triggerMappings: [],
      touchMappings: [],
      bindings: [],
      chords: [],
      sequences: [],
      layers: []
    )
  }

  /// Whether this profile can synthesize keyboard, pointer, or scroll input.
  /// Includes inactive layers and alternate activation destinations so permission loss cannot
  /// become a partial mapping. System-only profiles retain their previous permission contract.
  public var requiresSystemInputAccess: Bool {
    if stickMappings.contains(where: { $0.mode != .steering })
      || touchMappings.contains(where: { $0.mode == .pointer })
    {
      return true
    }
    if outputPolicy.virtualGamepad == .disabled || gyroOutput.mode == .mouse { return true }
    if Self.containsSystemInput(bindings: bindings, chords: chords, sequences: sequences) {
      return true
    }
    return layers.contains {
      Self.containsSystemInput(bindings: $0.bindings, chords: $0.chords, sequences: $0.sequences)
    }
  }

  private static func containsSystemInput(
    bindings: [RemappingBinding],
    chords: [RemappingChord],
    sequences: [RemappingSequence]
  ) -> Bool {
    bindings.flatMap(\.expandedActions).contains {
      $0.destination.isSystemInput || $0.longHold?.destination.isSystemInput == true
        || $0.doubleTap?.destination.isSystemInput == true
    } || chords.contains { $0.destination.isSystemInput }
      || sequences.contains { $0.destination.isSystemInput }
  }

  private static func containsVirtualGamepadOutput(
    bindings: [RemappingBinding],
    chords: [RemappingChord],
    sequences: [RemappingSequence]
  ) -> Bool {
    bindings.flatMap(\.expandedActions).contains { binding in
      binding.destination.isVirtualGamepad || binding.longHold?.destination.isVirtualGamepad == true
        || binding.doubleTap?.destination.isVirtualGamepad == true
    } || chords.contains { $0.destination.isVirtualGamepad }
      || sequences.contains { $0.destination.isVirtualGamepad }
  }

  private func replacingInputConfiguration(
    outputPolicy: RemappingOutputPolicy,
    motionTuning: RemappingMotionTuning? = nil,
    gyroOutput: RemappingGyroOutput? = nil,
    stickMappings: [RemappingStickMapping]? = nil,
    triggerMappings: [RemappingTriggerMapping]? = nil,
    touchMappings: [RemappingTouchMapping]? = nil,
    bindings: [RemappingBinding]? = nil,
    chords: [RemappingChord]? = nil,
    sequences: [RemappingSequence]? = nil,
    layers: [RemappingLayer]? = nil
  ) -> Self {
    Self(
      id: id,
      name: name,
      device: device,
      applicationScope: applicationScope,
      outputPolicy: outputPolicy,
      physicalColor: physicalColor,
      motionTuning: motionTuning ?? self.motionTuning,
      gyroOutput: gyroOutput ?? self.gyroOutput,
      joyConPair: joyConPair,
      stickMappings: stickMappings ?? self.stickMappings,
      triggerMappings: triggerMappings ?? self.triggerMappings,
      touchMappings: touchMappings ?? self.touchMappings,
      bindings: bindings ?? self.bindings,
      chords: chords ?? self.chords,
      sequences: sequences ?? self.sequences,
      layers: layers ?? self.layers
    )
  }
}

extension RemappingDestination {
  /// Identifies destinations that require operating-system input-posting authorization.
  public var isSystemInput: Bool {
    switch self {
    case .keyboard, .mouseButton, .mouseMovement, .scroll: true
    case .gamepadButton, .gamepadDpad, .gamepadAxis, .physical: false
    }
  }

  var isVirtualGamepad: Bool {
    switch self {
    case .gamepadButton, .gamepadDpad, .gamepadAxis: true
    case .keyboard, .mouseButton, .mouseMovement, .scroll, .physical: false
    }
  }
}
