import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  func waitForExclusiveAccess() async {
    await waitForScopedRefreshCompletion()
    await waitForExclusiveOperationCompletion()
  }

  func resumeDeferredRefreshes() {
    resumeExclusiveOperationWaiters()
    schedulePendingScopedRefresh()
  }

  /// Publishes the remapping snapshot a profile request returned as the authoritative state.
  func applyRemappingSnapshot(_ snapshot: ApplicationServiceRemappingSnapshotPayload) {
    remappingState = .available(snapshot)
    postEventAccessState = .available(snapshot.postEventAccess)
    postEventAccessGeneration += 1
    authoritativePostEventAccess = snapshot.postEventAccess
    updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
  }

  func updateStatusPermissions(_ permissions: RuntimePermissionSummary) {
    guard case .available(let status) = statusState else { return }
    let nextState = RuntimeStatusState.available(status.applyingPermissions(permissions))
    if statusState != nextState { statusState = nextState }
  }

  func updateStatusPostEventAccess(_ state: RemappingPostEventAccessState?) {
    guard case .available(let status) = statusState else { return }
    let nextState = RuntimeStatusState.available(status.applyingPostEventAccess(state))
    if statusState != nextState { statusState = nextState }
  }

  func updateStatusRemappingSnapshot(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    postEventAccess: RemappingPostEventAccessState?
  ) {
    guard case .available(let status) = statusState else { return }
    let nextState = RuntimeStatusState.available(
      status.applyingRemappingSnapshot(snapshot, postEventAccess: postEventAccess)
    )
    if statusState != nextState { statusState = nextState }
  }
}
