import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Publishes the automatic dispatcher for the connected controllers after every earlier queued
  /// change; true when output is live.
  func activateCompatibilityBackendForCurrentDevices() async -> Bool {
    await compatibilityTransitionCoordinator.enqueue { [weak self] in
      await self?.performCompatibilityBackendActivation() ?? false
    }
  }

  /// Builds, activates, and publishes the automatic dispatcher when no output is live. A failure
  /// closes the candidate and leaves output unavailable with the failure as its status.
  func performCompatibilityBackendActivation() async -> Bool {
    guard !isCompatibilityServerStopped() else { return false }
    let isLive = userSpaceLock.withLock { userSpaceEnabled && userSpaceDispatcher != nil }
    if isLive { return true }

    let candidate: UserSpaceDispatcherBuild
    do {
      candidate = try await withCompatibilityTimeout(
        compatibilityTransitionTimeouts.stageNanoseconds,
        clock: compatibilityTransitionClock,
        error: .stageTimedOut
      ) {
        try self.buildUserSpaceDispatcher()
      } onLateSuccess: { late in
        _ = await self.closeCompatibilityBackend(late.closeSlot)
      }
    } catch {
      recordCompatibilityBackendUnavailable(error)
      return false
    }
    guard !isCompatibilityServerStopped() else {
      _ = await closeCompatibilityBackend(candidate.closeSlot)
      return false
    }

    do {
      try await activateCompatibilityDispatcher(
        candidate.dispatcher,
        for: await connectedIdentifiers()
      )
    } catch {
      _ = await closeCompatibilityBackend(candidate.closeSlot)
      recordCompatibilityBackendUnavailable(error)
      return false
    }

    let published = userSpaceLock.withLock { () -> Bool in
      guard !compatibilityServerStopped else { return false }
      userSpaceDispatcher = candidate.dispatcher
      userSpaceCloseSlot = candidate.closeSlot
      dispatcher.setBackend(candidate.dispatcher)
      userSpaceEnabled = true
      userSpaceStatus = candidate.status
      return true
    }
    guard published else {
      _ = await closeCompatibilityBackend(candidate.closeSlot)
      return false
    }
    print("[ApplicationServiceServer] Compatibility virtual gamepad ready")
    return true
  }

  /// Activates `candidate` for `identifiers`, bounding each controller by the per-controller
  /// timeout and the whole set by the total timeout.
  ///
  /// - Throws: `CancellationError` when the server stops before a controller's activation.
  private func activateCompatibilityDispatcher(
    _ candidate: any CompatibilityUserSpaceOutputDispatching,
    for identifiers: [DeviceIdentifier]
  ) async throws {
    let timeout = compatibilityTransitionTimeouts.activationNanoseconds(for: identifiers.count)
    guard !identifiers.isEmpty,
      let scoped = candidate as? any CompatibilityUserSpaceOutputControllerActivating
    else {
      try await withCompatibilityTimeout(
        timeout,
        clock: compatibilityTransitionClock,
        error: .activationTimedOut
      ) { try await candidate.activate(for: identifiers) }
      return
    }
    let started = compatibilityTransitionClock.now()
    for identifier in identifiers {
      guard !isCompatibilityServerStopped() else { throw CancellationError() }
      let now = compatibilityTransitionClock.now()
      let elapsed = now >= started ? now - started : 0
      let remaining = timeout > elapsed ? timeout - elapsed : 0
      try await withCompatibilityTimeout(
        min(remaining, compatibilityTransitionTimeouts.perControllerNanoseconds),
        clock: compatibilityTransitionClock,
        error: .activationTimedOut
      ) { try await scoped.activate(controller: identifier) }
    }
  }

  private func recordCompatibilityBackendUnavailable(_ error: any Error) {
    userSpaceLock.withLock {
      guard !compatibilityServerStopped else { return }
      userSpaceStatus = "error: \(error)"
    }
    print("[ApplicationServiceServer] Compatibility virtual gamepad unavailable: \(error)")
  }

  /// Every connected controller once, in provider order.
  func connectedIdentifiers() async -> [DeviceIdentifier] {
    var seen = Set<DeviceIdentifier>()
    return (await connectedIdentifierProvider()).filter { seen.insert($0).inserted }
  }
}
