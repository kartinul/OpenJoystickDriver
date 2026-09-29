import Foundation

extension RemappingBinding {
  var expandedActions: [RemappingBinding] {
    [self] + additionalActions.map { $0.binding(source: source, axisTuning: axisTuning) }
  }
}

extension RemappingDeviceState {
  func actionBinding(id: UUID) -> RemappingBinding? {
    let sources = Set(profile.bindings.map(\.source)).union(
      profile.layers.flatMap { $0.bindings.map(\.source) }
    )
    for source in sources {
      if let action = binding(for: source)?.expandedActions.first(where: { $0.id == id }) {
        return action
      }
    }
    return nil
  }
}

extension RemappingEngineState {
  mutating func cancelActions(
    for sources: Set<RemappingSource>,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let bindings = device.profile.bindings + device.profile.layers.flatMap(\.bindings)
    let identifiers = Set(
      bindings.filter { sources.contains($0.source) }.flatMap { $0.expandedActions.map(\.id) }
    )
    var actions: [RemappingEngineAction] = []
    for id in identifiers.sorted(by: { $0.uuidString < $1.uuidString }) {
      if let destination = device.outputs.heldBindings[id] {
        actions += setBinding(id, destination: destination, isDown: false, device: &device)
      }
      device.outputs.activations.removeValue(forKey: id)
      device.outputs.armedReleaseBindings.remove(id)
      device.outputs.pulseDeadlines.removeValue(forKey: id)
      device.outputs.turbos.removeValue(forKey: id)
      device.outputs.continuous.removeValue(forKey: id)
    }
    return actions
  }

  mutating func processAction(
    _ binding: RemappingBinding,
    isActive: Bool,
    suppressed: Bool,
    device: inout RemappingDeviceState,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard !suppressed else { return [] }
    let id = binding.id
    let destination = binding.destination
    if binding.behavior != .hold {
      if !isActive {
        guard binding.behavior == .tapOnRelease,
          device.outputs.armedReleaseBindings.remove(id) != nil
        else { return [] }
        return tapBinding(id, destination: destination, device: &device)
      }
      switch binding.behavior {
      case .hold: return []
      case .press: return setBinding(id, destination: destination, isDown: true, device: &device)
      case .release: return releaseDestination(destination, device: &device)
      case .toggle:
        return setBinding(
          id,
          destination: destination,
          isDown: device.outputs.heldBindings[id] == nil,
          device: &device
        )
      case .tapOnPress: return tapBinding(id, destination: destination, device: &device)
      case .tapOnRelease:
        device.outputs.armedReleaseBindings.insert(id)
        return []
      case .pulse:
        let duration = UInt64(binding.pulseDurationMs * 1_000_000)
        let (deadline, overflow) = uptime.addingReportingOverflow(duration)
        device.outputs.pulseDeadlines[id] = overflow ? .max : deadline
        return setBinding(id, destination: destination, isDown: true, device: &device)
      }
    }
    if binding.longHold != nil || binding.doubleTap != nil {
      return processTimedAction(binding, isActive: isActive, device: &device, at: uptime)
    }
    if let turbo = binding.turbo {
      if isActive {
        device.outputs.turbos[id] = RemappingTurboOutput(
          destination: destination,
          configuration: turbo,
          startedAt: uptime,
          outputIsDown: true
        )
      } else {
        device.outputs.turbos.removeValue(forKey: id)
      }
    }
    return setBinding(id, destination: destination, isDown: isActive, device: &device)
  }

  private mutating func processTimedAction(
    _ binding: RemappingBinding,
    isActive: Bool,
    device: inout RemappingDeviceState,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    var tracker = device.outputs.activations[binding.id] ?? RemappingActivationTracker()
    if isActive {
      var secondTap = false
      if let doubleTap = binding.doubleTap, let released = tracker.releaseUptime,
        tracker.pendingDefault
      {
        let window = UInt64(doubleTap.windowMs * 1_000_000)
        secondTap = uptime >= released && uptime - released < window
        if !secondTap {
          actions += tapBinding(binding.id, destination: binding.destination, device: &device)
        }
      }
      tracker = RemappingActivationTracker(
        pressUptime: uptime,
        tapCount: secondTap ? 2 : 1,
        pendingDefault: true
      )
      if secondTap, let doubleTap = binding.doubleTap {
        tracker.pendingDefault = false
        tracker.firedBindingID = binding.id
        actions += setBinding(
          binding.id,
          destination: doubleTap.destination,
          isDown: true,
          device: &device
        )
      }
    } else {
      tracker.releaseUptime = uptime
      if tracker.firedBindingID != nil, !tracker.pendingDefault {
        actions += setBinding(
          binding.id,
          destination: binding.destination,
          isDown: false,
          device: &device
        )
        tracker = RemappingActivationTracker()
      } else if tracker.pendingDefault, binding.doubleTap == nil {
        actions += tapBinding(binding.id, destination: binding.destination, device: &device)
        tracker = RemappingActivationTracker()
      }
    }
    device.outputs.activations[binding.id] = tracker
    return actions
  }
}
