extension RemappingEngineState {
  mutating func processMotion(
    _ sample: ControllerMotionSample,
    for identifier: DeviceIdentifier
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let processed = device.motion.motion.process(sample, tuning: device.effectiveMotionTuning)
    let motionStick = device.updateMotionStick(processed)
    var actions = motionStick.actions
    devices[identifier] = device
    for change in motionStick.leanChanges {
      actions += setSource(
        .motionLean(change.direction),
        isActive: change.isActive,
        for: identifier,
        at: device.lastUptime
      )
    }
    guard var device = devices[identifier] else { return actions }
    guard device.isGyroActive else {
      actions += device.clearGyroStick()
      devices[identifier] = device
      return actions
    }
    if device.motion.gyroAwaitingBaseline, processed != nil {
      device.motion.gyroAwaitingBaseline = false
      actions += device.clearGyroStick()
      devices[identifier] = device
      return actions
    }
    let trackball = device.processTrackball(processed)
    if device.profile.gyroOutput.mode == .leftStick || device.profile.gyroOutput.mode == .rightStick
    {
      actions += device.updateGyroStick(processed, velocity: trackball?.velocity)
      devices[identifier] = device
      return actions
    }
    devices[identifier] = device
    guard let processed, processed.deltaTime > 0, device.profile.gyroOutput.mode == .mouse else {
      return actions
    }
    let scale = device.profile.gyroOutput.pointerPointsPerDegree
    // Player/world projections already reverse yaw relative to local controller Y.
    let yawSign = device.effectiveMotionTuning.space == .local ? -1.0 : 1.0
    let yaw = trackball?.yawDegrees ?? processed.tunedGyro.yawDegreesPerSecond * processed.deltaTime
    let pitch =
      trackball?.pitchDegrees ?? processed.tunedGyro.pitchDegreesPerSecond * processed.deltaTime
    let x = yaw * scale * yawSign
    let y = -pitch * scale
    guard x.isFinite, y.isFinite, x != 0 || y != 0 else { return actions }
    actions.append(.system(.pointerDelta(x: x, y: y)))
    return actions
  }
}

extension RemappingDeviceState {
  mutating func processTrackball(
    _ processed: RemappingProcessedMotion?
  ) -> RemappingMotionTrackball.Step? {
    guard let settings = profile.gyroOutput.trackball else { return nil }
    guard let processed else {
      if motion.motion.latest == nil { motion.gyroTrackball.reset() }
      return nil
    }
    let held = activeSources.contains(settings.source)
    return motion.gyroTrackball.process(
      processed.tunedGyro,
      deltaTime: processed.deltaTime,
      pitchHeld: held && settings.axes != .yaw,
      yawHeld: held && settings.axes != .pitch,
      decayHalvingsPerSecond: settings.decayHalvingsPerSecond
    )
  }

  var isGyroActive: Bool {
    let held = profile.gyroOutput.activationSource.map { activeSources.contains($0) } ?? false
    switch profile.gyroOutput.activationMode {
    case .always: return true
    case .whileHeld: return held
    case .whileReleased: return !held
    case .toggle: return motion.gyroToggleActive
    }
  }

  mutating func updateGyroStick(
    _ processed: RemappingProcessedMotion?,
    velocity: RemappingGyroProjection? = nil
  ) -> [RemappingEngineAction] {
    guard let processed else { return motion.motion.latest == nil ? clearGyroStick() : [] }
    guard processed.deltaTime > 0 else { return clearGyroStick() }
    let output = profile.gyroOutput
    let yawSign = effectiveMotionTuning.space == .local ? -1.0 : 1.0
    let velocity = velocity ?? processed.tunedGyro
    let x = velocity.yawDegreesPerSecond * yawSign / output.fullStickDegreesPerSecond
    let y = velocity.pitchDegreesPerSecond / output.fullStickDegreesPerSecond
    guard x.isFinite, y.isFinite else { return clearGyroStick() }
    let horizontal: RemappingAxis = output.mode == .leftStick ? .leftStickX : .rightStickX
    let vertical: RemappingAxis = output.mode == .leftStick ? .leftStickY : .rightStickY
    let contribution = RemappingGamepadState(axes: [
      horizontal: max(-1, min(1, x)), vertical: max(-1, min(1, y)),
    ])
    if x == 0, y == 0 { return clearGyroStick() }
    let (deadline, overflow) = lastUptime.addingReportingOverflow(100_000_000)
    motion.gyroDeadline = overflow ? .max : deadline
    guard let state = outputs.gamepad.update(contribution, for: motion.gyroBindingID) else {
      return []
    }
    return [.gamepad(state, identifier)]
  }

  mutating func clearGyroStick() -> [RemappingEngineAction] {
    motion.gyroDeadline = nil
    motion.gyroTrackball.reset()
    guard let state = outputs.gamepad.update(.neutral, for: motion.gyroBindingID) else { return [] }
    return [.gamepad(state, identifier)]
  }
}
