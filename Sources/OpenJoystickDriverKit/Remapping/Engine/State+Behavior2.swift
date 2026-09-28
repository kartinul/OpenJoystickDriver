import Foundation

extension RemappingEngineState {

  mutating func handleLayerActivator(
    _ source: RemappingSource,
    isActive: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction]? {
    let profile = device.profile
    var actions: [RemappingEngineAction] = []
    var handled = false
    let previousTuning = device.effectiveMotionTuning
    let previousLayers = device.activeLayers

    for layer in profile.layers where layer.activator == source {
      handled = true
      switch layer.activationMode {
      case .hold:
        if isActive {
          if !device.activeLayers.contains(layer.id) { device.activeLayers.append(layer.id) }
        } else {
          device.activeLayers.removeAll { $0 == layer.id }
        }
      case .toggle:
        if isActive {
          if device.layerToggleState.contains(layer.id) {
            device.layerToggleState.remove(layer.id)
            device.activeLayers.removeAll { $0 == layer.id }
          } else {
            device.layerToggleState.insert(layer.id)
            device.activeLayers.append(layer.id)
          }
        }
      }
    }

    guard handled else { return nil }
    guard previousLayers != device.activeLayers else { return [] }
    if previousTuning != device.effectiveMotionTuning {
      actions += device.clearGyroStick()
      actions += device.clearMotionSteering()
      device.motionStickDeadline = nil
      for direction in device.activeMotionLeans {
        let source = RemappingSource.motionLean(direction)
        actions += cancelActions(for: [source], device: &device)
        device.activeSources.remove(source)
        device.sourcePressTimes.removeValue(forKey: source)
      }
      device.activeMotionLeans.removeAll()
      device.motion.resetCalibration()
      device.gyroAwaitingBaseline = true
    }
    actions += reconcileLayerOutputs(device: &device)
    device.sequenceHistory.removeAll()
    device.deferredSequences.removeAll()
    device.replayedChordSources.formUnion(device.pendingChordPresses.map(\.source))
    device.consumedChordSources.formUnion(device.pendingChordPresses.map(\.source))
    device.pendingChordPresses.removeAll()

    actions += processChords(for: &device)
    return actions
  }

  func sourceCompletesChord(_ source: RemappingSource, in device: RemappingDeviceState) -> Bool {
    device.selectedChords().contains { $0.sources.contains(source) }
  }

  mutating func processChords(
    for device: inout RemappingDeviceState,
    releasing source: RemappingSource? = nil
  ) -> [RemappingEngineAction] {
    let selected = device.selectedChords(releasing: source)
    let selectedIDs = Set(selected.map(\.id))
    var actions: [RemappingEngineAction] = []
    let retiredIDs = device.activeChords.subtracting(selectedIDs).sorted {
      $0.uuidString < $1.uuidString
    }
    for id in retiredIDs {
      guard let destination = device.heldBindings[id] else { continue }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    for chord in selected where !device.activeChords.contains(chord.id) {
      actions += cancelActions(for: chord.sources, device: &device)
      device.sequenceHistory.removeAll { chord.sources.contains($0.source) }
      device.deferredSequences.removeAll { !$0.awaitingSources.isDisjoint(with: chord.sources) }
      device.pendingChordPresses.removeAll { chord.sources.contains($0.source) }
      device.consumedChordSources.formUnion(chord.sources)
      actions += setBinding(chord.id, destination: chord.destination, isDown: true, device: &device)
    }
    device.activeChords = selectedIDs
    return actions
  }

  /// Checks if recent input history matches any defined sequence.
  mutating func processSequences(
    for device: inout RemappingDeviceState,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions = commitDeferredSequences(device: &device)
    let allSequences = device.effectiveSequences

    for sequence in allSequences {
      let sources = sequence.sources
      guard device.sequenceHistory.count >= sources.count else { continue }
      let windowNs = UInt64(sequence.windowMs * remappingStateNanosecondsPerMillisecond)
      let tail = Array(device.sequenceHistory.suffix(sources.count))

      guard tail.count == sources.count else { continue }
      let matches = zip(tail, sources).allSatisfy { $0.0.source == $0.1 }
      guard matches else { continue }

      guard let firstUptime = tail.first?.uptime, let lastUptime = tail.last?.uptime else {
        continue
      }
      guard lastUptime >= firstUptime, lastUptime - firstUptime <= windowNs else { continue }

      let awaitingSources = Set(tail.filter(\.awaitingChord).map(\.source))
      if awaitingSources.isEmpty {
        actions += tapBinding(sequence.id, destination: sequence.destination, device: &device)
      } else {
        device.deferredSequences.append(
          RemappingDeferredSequence(sequence: sequence, awaitingSources: awaitingSources)
        )
      }
      // Each deferred match owns at least one pending press, which this clear removes
      // from history. It cannot create another match until that press resolves.
      device.sequenceHistory.removeAll()
      break
    }

    device.pruneSequenceHistory(at: uptimeNanoseconds)
    return actions
  }
}
