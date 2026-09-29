import Foundation
import OpenJoystickDriverKit

extension RuntimeProfileDraft {
  func settingLayerMotionTuning(_ tuning: RemappingMotionTuning?, for layerID: UUID) throws -> Self
  { try editing { try $0.updateLayer(layerID, motionTuning: .some(tuning)) } }

  func settingStickMappings(_ mappings: [RemappingStickMapping]) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(stickMappings: mappings)))
  }

  func settingTriggerMappings(_ mappings: [RemappingTriggerMapping]) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(triggerMappings: mappings)))
  }

  func settingTouchMappings(_ mappings: [RemappingTouchMapping]) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(touchMappings: mappings)))
  }

  func settingMotionTuning(
    _ tuning: RemappingMotionTuning,
    gyroOutput: RemappingGyroOutput? = nil
  ) throws -> Self {
    Self(
      profile: try Self.validate(profile.replacing(motionTuning: tuning, gyroOutput: gyroOutput))
    )
  }

  func settingDestination(_ destination: RemappingDestination, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func settingSource(_ source: RemappingSource, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      let tuning: RemappingAxisTuning?
      switch source {
      case .axis, .axisDirection: tuning = binding.axisTuning ?? .default
      case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
        tuning = nil
      }
      let destination = Self.destination(for: source, preserving: binding.destination)
      return RemappingBinding(
        id: binding.id,
        source: source,
        destination: destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: tuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  private static func destination(
    for source: RemappingSource,
    preserving current: RemappingDestination
  ) -> RemappingDestination {
    let options = DestinationOption.options(for: source, including: current)
    if let preserved = options.first(where: { $0.destination == current }) {
      return preserved.destination
    }
    return options.first?.destination ?? current
  }

  func settingAxisTuning(_ axisTuning: RemappingAxisTuning?, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func settingBindingBehaviors(
    behavior: RemappingBindingBehavior? = nil,
    pulseDurationMs: Double? = nil,
    turbo: RemappingTurbo?,
    longHold: RemappingLongHold?,
    doubleTap: RemappingDoubleTap?,
    for bindingID: UUID
  ) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: behavior ?? binding.behavior,
        pulseDurationMs: (behavior ?? binding.behavior) == .pulse
          ? pulseDurationMs ?? binding.pulseDurationMs : RemappingBinding.defaultPulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: turbo,
        longHold: longHold,
        doubleTap: doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func addingBinding(
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil
  ) throws -> Self {
    let tuning: RemappingAxisTuning?
    switch source {
    case .axis, .axisDirection: tuning = axisTuning ?? .default
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
      tuning = nil
    }
    let binding = RemappingBinding(source: source, destination: destination, axisTuning: tuning)
    return Self(
      profile: try Self.validate(profile.replacing(bindings: profile.bindings + [binding]))
    )
  }

  func removingBinding(_ bindingID: UUID) throws -> Self {
    guard profile.bindings.contains(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    let bindings = profile.bindings.filter { $0.id != bindingID }
    return Self(profile: try Self.validate(profile.replacing(bindings: bindings)))
  }
}
