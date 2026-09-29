import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// Refreshes connection- and profile-sensitive state without replacing the UI with loading state.
  @discardableResult
  func refreshLiveStatus() async -> Bool { await enqueueScopedRefresh(.live) }

  /// Refreshes controller inventory and permission observations without touching unrelated panes.
  func refreshControllerInventory() async { _ = await enqueueScopedRefresh(.inventory) }

  private func enqueueScopedRefresh(_ refresh: ScopedRefresh) async -> Bool {
    let previousStatusState = statusState
    let previousRemappingState = remappingState
    let previousPermissionState = permissionState
    let previousPostEventAccessState = postEventAccessState
    let previousLoadState = loadState
    pendingScopedRefreshes.formUnion(refresh)
    guard !isScopedRefreshInFlight, !fullRefreshInFlight, !mutationInFlight else {
      await withCheckedContinuation { scopedRefreshWaiters.append($0) }
      return scopedRefreshChanged(
        statusState: previousStatusState,
        remappingState: previousRemappingState,
        permissionState: previousPermissionState,
        postEventAccessState: previousPostEventAccessState,
        loadState: previousLoadState
      )
    }
    setScopedRefreshInFlight(true)
    defer {
      setScopedRefreshInFlight(false)
      let waiters = scopedRefreshWaiters
      scopedRefreshWaiters = []
      waiters.forEach { $0.resume() }
    }

    while !pendingScopedRefreshes.isEmpty, !fullRefreshInFlight, !mutationInFlight {
      let refreshes = pendingScopedRefreshes
      pendingScopedRefreshes = []
      liveStatusGeneration += 1
      let generation = liveStatusGeneration
      await refreshStatusRetainingPresentation(generation: generation)

      guard refreshes.contains(.live) else { continue }
      do {
        let snapshot = try await gateway.remappingSnapshot()
        guard generation == liveStatusGeneration else { continue }
        let nextRemappingState = RuntimeRemappingState.available(snapshot)
        if remappingState != nextRemappingState { remappingState = nextRemappingState }
        authoritativePostEventAccess = snapshot.postEventAccess
        let nextPostEventAccessState = RuntimePostEventAccessLoadState.available(
          snapshot.postEventAccess
        )
        if postEventAccessState != nextPostEventAccessState {
          postEventAccessState = nextPostEventAccessState
        }
        updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
      } catch {
        // Keep the last known remapping state during an unobtrusive background refresh.
      }
    }
    return scopedRefreshChanged(
      statusState: previousStatusState,
      remappingState: previousRemappingState,
      permissionState: previousPermissionState,
      postEventAccessState: previousPostEventAccessState,
      loadState: previousLoadState
    )
  }

  private func setScopedRefreshInFlight(_ isInFlight: Bool) {
    isScopedRefreshInFlight = isInFlight
    scopedRefreshInFlightPublisher.send(isInFlight)
  }

  private func scopedRefreshChanged(
    statusState previousStatusState: RuntimeStatusState,
    remappingState previousRemappingState: RuntimeRemappingState,
    permissionState previousPermissionState: RuntimePermissionLoadState,
    postEventAccessState previousPostEventAccessState: RuntimePostEventAccessLoadState,
    loadState previousLoadState: RuntimeLoadState
  ) -> Bool {
    previousStatusState != statusState || previousRemappingState != remappingState
      || previousPermissionState != permissionState
      || previousPostEventAccessState != postEventAccessState || previousLoadState != loadState
  }

  private func refreshStatusRetainingPresentation(generation: Int) async {
    do {
      let payload = try await gateway.status()
      guard generation == liveStatusGeneration else { return }
      let previousStatus: RuntimeStatusPresentation?
      if case .available(let status) = statusState {
        previousStatus = status
      } else {
        previousStatus = nil
      }
      let permissions: RuntimePermissionSummary
      switch permissionState {
      case .requesting:
        permissions =
          authoritativePermissionSummary
          ?? RuntimePermissionSummary(inputMonitoring: .unknown, accessibility: .unknown)
      case .loading, .available, .unavailable, .error:
        permissions = RuntimePermissionSummary(status: payload)
        authoritativePermissionSummary = permissions
      }
      let nextStatusState = RuntimeStatusState.available(
        RuntimeStatusPresentation(
          payload: payload,
          postEventAccess: authoritativePostEventAccess ?? previousStatus?.postEventAccess,
          requiresPostEventAccess: previousStatus?.requiresPostEventAccess
        ).applyingPermissions(permissions)
      )
      if statusState != nextStatusState { statusState = nextStatusState }
      publishControllerInventory(payload.connectedDevices)
      if case .requesting = permissionState {
        // The explicit permission request remains authoritative until its response arrives.
      } else {
        let nextPermissionState = RuntimePermissionLoadState.available(permissions)
        if permissionState != nextPermissionState { permissionState = nextPermissionState }
      }
      if loadState != .available { loadState = .available }
      if liveStatusError != nil { liveStatusError = nil }
    } catch {
      guard generation == liveStatusGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      if case .loading = statusState {
        statusState =
          RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      } else if liveStatusError != message {
        // The last list stays visible, but must not pass for current while reads keep failing.
        liveStatusError = message
      }
    }
  }

  func publishControllerInventory(_ devices: [ApplicationServiceDeviceDescription]) {
    let connectedModels = Set(devices.map(RuntimeControllerModel.init))
    let staleModels = virtualHIDProfileOverrideStates.filter { model, state in
      !state.inFlight && !connectedModels.contains(model)
    }.keys
    for model in staleModels { virtualHIDProfileOverrideStates[model] = nil }
    let identifiers = devices.map(\.runtimeIdentifier)
    guard identifiers != controllerRuntimeIdentifiers else { return }
    controllerRuntimeIdentifiers = identifiers
    controllerInventoryGeneration &+= 1
  }

  func waitForScopedRefreshCompletion() async {
    guard isScopedRefreshInFlight else { return }
    await withCheckedContinuation { scopedRefreshWaiters.append($0) }
  }

  func waitForExclusiveOperationCompletion() async {
    while fullRefreshInFlight || mutationInFlight {
      await withCheckedContinuation { exclusiveOperationWaiters.append($0) }
    }
  }

  func resumeExclusiveOperationWaiters() {
    let waiters = exclusiveOperationWaiters
    exclusiveOperationWaiters = []
    waiters.forEach { $0.resume() }
  }

  func schedulePendingScopedRefresh() {
    guard !pendingScopedRefreshes.isEmpty else { return }
    Task { @MainActor in _ = await enqueueScopedRefresh([]) }
  }
}
