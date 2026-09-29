import Foundation
import OpenJoystickDriverKit

extension RuntimeProfileDraft {

  func addingChord(
    sources: Set<RemappingSource>,
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) throws -> Self {
    try editing {
      try $0.addChord(sources: sources, destination: destination, mode: mode, windowMs: windowMs)
    }
  }

  func removingChord(_ chordID: UUID) throws -> Self { try editing { try $0.removeChord(chordID) } }

  func addingSequence(
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws -> Self {
    try editing {
      try $0.addSequence(sources: sources, windowMs: windowMs, destination: destination)
    }
  }

  func removingSequence(_ sequenceID: UUID) throws -> Self {
    try editing { try $0.removeSequence(sequenceID) }
  }

  func addingLayer(
    name: String,
    activator: RemappingSource,
    activationMode: RemappingLayerActivation
  ) throws -> Self {
    try editing {
      try $0.addLayer(name: name, activator: activator, activationMode: activationMode)
    }
  }

  func removingLayer(_ layerID: UUID) throws -> Self { try editing { try $0.removeLayer(layerID) } }

  func settingLayerBinding(
    layerID: UUID,
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    doubleTap: RemappingDoubleTap? = nil
  ) throws -> Self {
    try editing { profile in
      let existing = try profile.layer(layerID).bindings.first { $0.source == source }
      let binding = RemappingBinding(
        id: existing?.id ?? UUID(),
        source: source,
        destination: destination,
        behavior: existing?.behavior ?? .hold,
        pulseDurationMs: existing?.pulseDurationMs ?? RemappingBinding.defaultPulseDurationMs,
        axisTuning: axisTuning ?? Self.defaultTuning(for: source),
        turbo: turbo,
        longHold: longHold,
        doubleTap: doubleTap,
        additionalActions: existing?.additionalActions ?? []
      )
      try profile.setLayerBinding(binding, in: layerID)
    }
  }

  func settingLayerBindingAxisTuning(
    layerID: UUID,
    bindingID: UUID,
    axisTuning: RemappingAxisTuning
  ) throws -> Self {
    try replacingLayerBinding(layerID: layerID, bindingID: bindingID) { binding in
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

  func settingLayerBindingBehaviors(
    behavior: RemappingBindingBehavior? = nil,
    pulseDurationMs: Double? = nil,
    layerID: UUID,
    bindingID: UUID,
    turbo: RemappingTurbo?,
    longHold: RemappingLongHold?,
    doubleTap: RemappingDoubleTap?
  ) throws -> Self {
    try replacingLayerBinding(layerID: layerID, bindingID: bindingID) { binding in
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

  func removingLayerBinding(layerID: UUID, bindingID: UUID) throws -> Self {
    try editing { profile in
      let bindings = try profile.layer(layerID).bindings
      guard bindings.contains(where: { $0.id == bindingID }) else {
        throw RuntimeProfileDraftError.bindingNotFound(bindingID)
      }
      try profile.updateLayer(layerID, bindings: bindings.filter { $0.id != bindingID })
    }
  }

  func replacingLayerBinding(
    layerID: UUID,
    bindingID: UUID,
    transform: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    try editing { profile in
      var bindings = try profile.layer(layerID).bindings
      guard let bindingIndex = bindings.firstIndex(where: { $0.id == bindingID }) else {
        throw RuntimeProfileDraftError.bindingNotFound(bindingID)
      }
      bindings[bindingIndex] = transform(bindings[bindingIndex])
      try profile.updateLayer(layerID, bindings: bindings)
    }
  }

  func replacingBinding(
    _ bindingID: UUID,
    _ makeBinding: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    guard let index = profile.bindings.firstIndex(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    var bindings = profile.bindings
    bindings[index] = makeBinding(bindings[index])
    return Self(profile: try Self.validate(profile.replacing(bindings: bindings)))
  }

  /// Applies a shared Kit edit and maps its errors to draft errors.
  func editing(_ edit: (inout RemappingProfile) throws -> Void) throws -> Self {
    var candidate = profile
    do { try edit(&candidate) } catch let error as RuntimeProfileDraftError {
      throw error
    } catch RemappingProfileEditingError.chordNotFound(let id) {
      throw RuntimeProfileDraftError.chordNotFound(id)
    } catch RemappingProfileEditingError.layerNotFound(let id) {
      throw RuntimeProfileDraftError.layerNotFound(id)
    } catch RemappingProfileEditingError.sequenceNotFound(let id) {
      throw RuntimeProfileDraftError.sequenceNotFound(id)
    } catch let error as RemappingValidationError {
      throw RuntimeProfileDraftError.validation(error)
    } catch { throw RuntimeProfileDraftError.validation(.encodingFailed) }
    return Self(profile: candidate)
  }

  static func defaultTuning(for source: RemappingSource) -> RemappingAxisTuning? {
    switch source {
    case .axis, .axisDirection: .default
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe: nil
    }
  }
  static func validate(_ profile: RemappingProfile) throws -> RemappingProfile {
    do {
      try profile.validate()
      return profile
    } catch let error as RemappingValidationError {
      throw RuntimeProfileDraftError.validation(error)
    } catch { throw RuntimeProfileDraftError.validation(.encodingFailed) }
  }
}
