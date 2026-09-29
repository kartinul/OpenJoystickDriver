import Foundation

/// Profile edits shared by the command-line editor and the profile editor draft.
///
/// Each mutating edit validates the complete result and leaves the profile unchanged when it
/// throws. Missing items throw `RemappingProfileEditingError`; invalid results throw the error
/// from `validate()`.
extension RemappingProfile {
  /// Returns a copy with the given fields replaced. A `nil` argument keeps the current value.
  /// The copy is not validated.
  package func replacing(
    name: String? = nil,
    device: RemappingDeviceScope? = nil,
    applicationScope: RemappingApplicationScope? = nil,
    outputPolicy: RemappingOutputPolicy? = nil,
    physicalColor: ControllerColor?? = nil,
    motionTuning: RemappingMotionTuning? = nil,
    gyroOutput: RemappingGyroOutput? = nil,
    joyConPair: RemappingJoyConPairSettings?? = nil,
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
      name: name ?? self.name,
      device: device ?? self.device,
      applicationScope: applicationScope ?? self.applicationScope,
      outputPolicy: outputPolicy ?? self.outputPolicy,
      physicalColor: physicalColor ?? self.physicalColor,
      motionTuning: motionTuning ?? self.motionTuning,
      gyroOutput: gyroOutput ?? self.gyroOutput,
      joyConPair: joyConPair ?? self.joyConPair,
      stickMappings: stickMappings ?? self.stickMappings,
      triggerMappings: triggerMappings ?? self.triggerMappings,
      touchMappings: touchMappings ?? self.touchMappings,
      bindings: bindings ?? self.bindings,
      chords: chords ?? self.chords,
      sequences: sequences ?? self.sequences,
      layers: layers ?? self.layers
    )
  }

  package func layer(_ layerID: UUID) throws -> RemappingLayer {
    guard let layer = layers.first(where: { $0.id == layerID }) else {
      throw RemappingProfileEditingError.layerNotFound(layerID)
    }
    return layer
  }

  package mutating func addChord(
    sources: Set<RemappingSource>,
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) throws {
    let chord = RemappingChord(
      sources: sources,
      destination: destination,
      mode: mode,
      windowMs: windowMs
    )
    try applyValidated(replacing(chords: chords + [chord]))
  }

  package mutating func removeChord(_ chordID: UUID) throws {
    guard chords.contains(where: { $0.id == chordID }) else {
      throw RemappingProfileEditingError.chordNotFound(chordID)
    }
    try applyValidated(replacing(chords: chords.filter { $0.id != chordID }))
  }

  package mutating func addSequence(
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws {
    let sequence = RemappingSequence(sources: sources, windowMs: windowMs, destination: destination)
    try applyValidated(replacing(sequences: sequences + [sequence]))
  }

  package mutating func removeSequence(_ sequenceID: UUID) throws {
    guard sequences.contains(where: { $0.id == sequenceID }) else {
      throw RemappingProfileEditingError.sequenceNotFound(sequenceID)
    }
    try applyValidated(replacing(sequences: sequences.filter { $0.id != sequenceID }))
  }

  package mutating func addLayer(
    name: String,
    activator: RemappingSource,
    activationMode: RemappingLayerActivation
  ) throws {
    let layer = RemappingLayer(name: name, activationMode: activationMode, activator: activator)
    try applyValidated(replacing(layers: layers + [layer]))
  }

  package mutating func removeLayer(_ layerID: UUID) throws {
    guard layers.contains(where: { $0.id == layerID }) else {
      throw RemappingProfileEditingError.layerNotFound(layerID)
    }
    try applyValidated(replacing(layers: layers.filter { $0.id != layerID }))
  }

  /// Replaces a layer's bindings or motion override. A `nil` argument keeps the current value;
  /// pass `.some(nil)` as `motionTuning` to clear the override.
  package mutating func updateLayer(
    _ layerID: UUID,
    bindings: [RemappingBinding]? = nil,
    motionTuning: RemappingMotionTuning?? = nil
  ) throws {
    guard let index = layers.firstIndex(where: { $0.id == layerID }) else {
      throw RemappingProfileEditingError.layerNotFound(layerID)
    }
    var updatedLayers = layers
    let layer = updatedLayers[index]
    updatedLayers[index] = RemappingLayer(
      id: layer.id,
      name: layer.name,
      activationMode: layer.activationMode,
      activator: layer.activator,
      bindings: bindings ?? layer.bindings,
      chords: layer.chords,
      sequences: layer.sequences,
      motionTuning: motionTuning ?? layer.motionTuning
    )
    try applyValidated(replacing(layers: updatedLayers))
  }

  /// Puts `binding` in the layer, replacing any layer binding for the same source.
  package mutating func setLayerBinding(_ binding: RemappingBinding, in layerID: UUID) throws {
    let bindings = try layer(layerID).bindings.filter { $0.source != binding.source }
    try updateLayer(layerID, bindings: bindings + [binding])
  }

  private mutating func applyValidated(_ candidate: Self) throws {
    try candidate.validate()
    self = candidate
  }
}
