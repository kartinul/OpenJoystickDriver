import Foundation

extension DeviceManager {
  func isCurrentUSBDetection(_ generation: UInt64) -> Bool {
    !isStopping && lifecycleGeneration == generation && !Task.isCancelled
  }

  func restoreAfterFailedWirelessDisconnect(
    identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    priorState: ControllerSessionState,
    failure: WirelessControllerDisconnectFailure,
    stage: WirelessControllerDisconnectStage,
    code: Int32? = nil,
    detail: String,
    restoreHIDClaim: Bool
  ) async -> WirelessControllerDisconnectResult {
    let claimResult =
      restoreHIDClaim
      ? await hidManager.reacquireInputClaim(locationID: identifier.locationID ?? 0) : .reacquired
    guard claimResult == .reacquired else {
      return WirelessControllerDisconnectResult(
        state: .suspended,
        failure: failure,
        failedStage: .restoreHIDClaim,
        systemCode: code,
        detail: "\(detail) HID recovery failed: \(Self.hidClaimFailureDescription(claimResult)).",
        recovery: "Reconnect the controller to restore input."
      )
    }
    if priorState == .active, !(await pipeline.resumeControllerSession()) {
      return WirelessControllerDisconnectResult(
        state: .suspended,
        failure: failure,
        failedStage: .restoreControllerSession,
        systemCode: code,
        detail: "\(detail) The HID claim was restored, but the controller session did not resume.",
        recovery: "Reconnect the controller to restore OpenJoystickDriver output."
      )
    }
    notifyControllerInventoryChanged()
    return WirelessControllerDisconnectResult(
      state: priorState,
      failure: failure,
      failedStage: stage,
      systemCode: code,
      detail: detail,
      recovery: "The previous controller session was restored; retry or reconnect the controller."
    )
  }

  static func hidClaimFailureDescription(_ result: PhysicalHIDClaimResult) -> String {
    switch result {
    case .released: "released"
    case .reacquired: "reacquired"
    case .unavailable: "the HID claim was unavailable"
    case .failed(.ioReturn(let code)): "IOKit code \(code)"
    }
  }

  static func bluetoothAddress(from serialNumber: String?) -> String? {
    guard let serialNumber else { return nil }
    let hexadecimal = serialNumber.filter(\.isHexDigit)
    guard hexadecimal.count == 12,
      serialNumber.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "-" })
    else { return nil }
    return stride(from: 0, to: hexadecimal.count, by: 2).map { offset in
      let start = hexadecimal.index(hexadecimal.startIndex, offsetBy: offset)
      let end = hexadecimal.index(start, offsetBy: 2)
      return hexadecimal[start..<end].uppercased()
    }.joined(separator: ":")
  }

  func notifyControllerInventoryChanged() {
    NotificationCenter.default.post(name: .ojdControllerInventoryDidChange, object: nil)
  }

  /// Stop all detection and pipelines.
  public func stop() async {
    // Sleep is system state; a stopped manager still waits for wake before a new start() runs.
    isStarted = false
    suspendedControllerIdentities.removeAll()
    guard !isStopping else { return }
    isStopping = true
    await tearDownControllerSessions()
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
    isStopping = false
  }

  /// Cancels detection and tears down every controller as if it were unplugged.
  ///
  /// Callers set `isStopping` first so in-flight admissions and startup work abandon their
  /// controllers instead of registering them.
  func tearDownControllerSessions() async {
    lifecycleGeneration &+= 1

    let pendingPermissionWatch = permissionWatchTask
    permissionWatchTask = nil
    pendingPermissionWatch?.cancel()

    for task in hidPeriodicOutputTasks.values { task.cancel() }
    hidPeriodicOutputTasks = [:]
    for task in rumbleStopTasks.values { task.cancel() }
    rumbleStopTasks = [:]
    rumbleStopTokens.removeAll()
    for task in detectionTasks { task.cancel() }
    detectionTasks = []

    await pendingPermissionWatch?.value

    let pendingHIDInitializations = Array(hidInitializationTasks.values)
    for initialization in pendingHIDInitializations { initialization.task.cancel() }
    hidInitializationTasks = [:]
    for initialization in pendingHIDInitializations { await initialization.task.value }
    permissionWatchTask?.cancel()
    permissionWatchTask = nil
    for pipeline in pipelines.values { await pipeline.acceptOnlyTeardownOutput() }
    // Pending output is dropped before teardown queues each controller's neutralization.
    for queue in hidOutputQueues.values { queue.cancelAll() }
    await ControllerTeardownOutput.$isActive.withValue(true) {
      for (identifier, pipeline) in pipelines {
        await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
        if let locationID = identifier.locationID {
          await sendHIDDeactivationWritesIfNeeded(pipeline: pipeline, locationID: locationID)
        }
        await pipeline.stop()
      }
    }
    // HID detection owns the backend session, so it closes only after the reports above.
    let pendingHIDDetection = hidDetectionTask
    hidDetectionTask = nil
    pendingHIDDetection?.cancel()
    await pendingHIDDetection?.value
    pipelines = [:]
    for task in rumbleStopTasks.values { task.cancel() }
    rumbleStopTasks = [:]
    rumbleStopTokens.removeAll()
    let hadDeviceInfo =
      !deviceInfos.isEmpty || !unboundDevices.isEmpty || !passThroughDevices.isEmpty
    deviceInfos.removeAll()
    hidRoleConnections.removeAll()
    unboundDevices.removeAll()
    unboundHIDClaims.removeAll()
    passThroughDevices.removeAll()
    for identifier in Array(hidOutputQueues.keys) { retireOutputQueue(for: identifier) }
    physicalOutputOwnership.removeAll()
    lastPhysicalHIDOutputNanoseconds = [:]
    if hadDeviceInfo { notifyControllerInventoryChanged() }
    // A drained retired queue has nothing left for a new queue to wait behind.
    for (identifier, queue) in retiredHIDOutputQueues {
      await queue.drain()
      if retiredHIDOutputQueues[identifier] === queue {
        retiredHIDOutputQueues.removeValue(forKey: identifier)
      }
    }
  }

  /// Enables or suppresses application-facing compatibility output for every active pipeline.
  public func setExternalOutputAllowed(_ allowed: Bool) async {
    guard externalOutputAllowed != allowed else { return }
    externalOutputAllowed = allowed
    for pipeline in pipelines.values { await pipeline.setExternalOutputAllowed(allowed) }
  }
}
