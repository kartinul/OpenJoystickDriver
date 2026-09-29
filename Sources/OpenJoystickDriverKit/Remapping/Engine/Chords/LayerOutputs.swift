import Foundation

extension RemappingEngineState {
  /// Releases contributions that no longer belong to the selected layer bindings.
  mutating func reconcileLayerOutputs(device: inout RemappingDeviceState) -> [RemappingEngineAction]
  {
    let profile = device.profile
    let sources = Set(profile.bindings.map(\.source)).union(
      profile.layers.flatMap { $0.bindings.map(\.source) }
    )
    var retained = Set(sources.flatMap { device.binding(for: $0)?.expandedActions.map(\.id) ?? [] })
    retained.formUnion(profile.chords.map(\.id))
    let activeIDs = Set(device.layers.activeLayers)
    for layer in profile.layers where activeIDs.contains(layer.id) {
      retained.formUnion(layer.chords.map(\.id))
    }
    var actions: [RemappingEngineAction] = []
    for id in device.outputs.heldBindings.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard !retained.contains(id), let destination = device.outputs.heldBindings[id] else {
        continue
      }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    for id in device.analog.virtualAxisBindings.sorted(by: { $0.uuidString < $1.uuidString })
    where !retained.contains(id) {
      if let state = device.outputs.gamepad.release(id) {
        actions.append(.gamepad(state, device.identifier))
      }
      device.analog.virtualAxisBindings.remove(id)
    }
    device.outputs.activations = device.outputs.activations.filter { retained.contains($0.key) }
    device.outputs.turbos = device.outputs.turbos.filter { retained.contains($0.key) }
    device.outputs.continuous = device.outputs.continuous.filter { retained.contains($0.key) }
    device.chords.activeChords.formIntersection(retained)
    device.outputs.armedReleaseBindings.formIntersection(retained)
    device.outputs.pulseDeadlines = device.outputs.pulseDeadlines.filter {
      retained.contains($0.key)
    }
    return actions
  }
}

extension RemappingDeviceState {
  var effectiveMotionTuning: RemappingMotionTuning {
    for id in layers.activeLayers.reversed() {
      if let tuning = profile.layers.first(where: { $0.id == id })?.motionTuning { return tuning }
    }
    return profile.motionTuning
  }
}
