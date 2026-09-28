import Foundation

extension RemappingDeviceState {
  /// Rebuilds the unmapped contribution using the same aggregate as explicit destinations.
  mutating func updatePassthrough(
    replayingAxis: (RemappingAxis, Float)? = nil
  ) -> [RemappingEngineAction] {
    guard profile.outputPolicy.virtualGamepad == .passthrough else { return [] }
    var reserved = reservedPassthroughSources
    // A trigger's analog axis and its click are one physical control: a profile that binds or
    // reserves either withholds both, so a released axis cannot leak back as a full click.
    for trigger in RemappingTriggerSource.allCases
    where trigger.passthroughSources.contains(where: {
      reserved.contains($0) || binding(for: $0) != nil
    }) { reserved.formUnion(trigger.passthroughSources) }
    var buttons: Set<RemappingButton> = []
    var directions: Set<RemappingDpadDirection> = []
    for source in activeSources where !reserved.contains(source) && binding(for: source) == nil {
      switch source {
      case .button(.rightPadClick): buttons.insert(.rightStick)
      case .button(let button): buttons.insert(button)
      case .dpad(let direction): directions.insert(direction)
      case .axis, .axisDirection, .triggerStage, .motionLean, .touchContact, .touchGrid,
        .touchSwipe:
        break
      }
    }
    var axes: [RemappingAxis: Double] = [:]
    var physicalValues = physicalAxes
    if let (axis, value) = replayingAxis { physicalValues[axis] = value }
    for (axis, value) in physicalValues {
      let sources: [RemappingSource] = [
        .axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive),
      ]
      guard sources.allSatisfy({ !reserved.contains($0) && binding(for: $0) == nil }) else {
        continue
      }
      axes[axis] = Double(value)
    }
    let contribution = RemappingGamepadState(buttons: buttons, dpad: directions, axes: axes)
    guard let state = gamepad.update(contribution, for: passthroughBindingID) else { return [] }
    return [.gamepad(state, identifier)]
  }

  /// Combination inputs stay out of raw output while their recognizers own them.
  private var reservedPassthroughSources: Set<RemappingSource> {
    var sources = Set(profile.layers.map(\.activator))
    for mapping in profile.stickMappings where !mapping.passthrough {
      let axes: [RemappingAxis] =
        mapping.source == .left ? [.leftStickX, .leftStickY] : [.rightStickX, .rightStickY]
      sources.formUnion(axes.map(RemappingSource.axis))
    }
    for mapping in profile.triggerMappings where !mapping.passthrough {
      sources.insert(.axis(mapping.source.axis))
    }
    let gyro = profile.gyroOutput
    if gyro.mode != .disabled, gyro.consumesActivationSource, let source = gyro.activationSource {
      sources.insert(source)
    }
    if gyro.mode != .disabled, let trackball = gyro.trackball, trackball.consumesSource {
      sources.insert(trackball.source)
    }
    sources.formUnion(pendingChordPresses.map(\.source))
    sources.formUnion(consumedChordSources)
    for chord in effectiveChords where chord.mode == .modifier { sources.formUnion(chord.sources) }
    for sequence in profile.sequences { sources.formUnion(sequence.sources) }
    let layerIDs = Set(activeLayers).union(layerToggleState)
    for layer in profile.layers where layerIDs.contains(layer.id) {
      for sequence in layer.sequences { sources.formUnion(sequence.sources) }
    }
    return sources
  }
}

extension RemappingTriggerSource {
  /// Every source that reads this physical trigger: its analog axis and its click.
  var passthroughSources: [RemappingSource] {
    [
      .axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive),
      .button(self == .left ? .leftTriggerClick : .rightTriggerClick),
    ]
  }
}
