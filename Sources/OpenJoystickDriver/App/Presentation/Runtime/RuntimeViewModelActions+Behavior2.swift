import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {

  func performMutation(
    request mutationRequest: RuntimeMutationRequest,
    conflictProfileID: UUID?,
    request: @escaping @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(mutationRequest) }
    await waitForScopedRefreshCompletion()
    await waitForExclusiveOperationCompletion()
    guard !mutationInFlight else { return rejectMutation(mutationRequest) }
    let operation = mutationRequest.operation
    let mutationID = mutationRequest.id
    mutationInFlight = true
    activeMutationOperation = operation
    activeMutationID = mutationID
    lastMutationOperation = nil
    lastMutationID = nil
    mutationState = .saving
    defer {
      mutationInFlight = false
      activeMutationOperation = nil
      activeMutationID = nil
      resumeExclusiveOperationWaiters()
      schedulePendingScopedRefresh()
    }
    do {
      let snapshot = try await request()
      remappingState = .available(snapshot)
      postEventAccessState = .available(snapshot.postEventAccess)
      postEventAccessGeneration += 1
      authoritativePostEventAccess = snapshot.postEventAccess
      updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
      lastMutationOperation = operation
      lastMutationID = mutationID
      switch operation {
      case .update(let profileID): mutationState = .succeeded(profileID: profileID)
      default: mutationState = .completed(operation)
      }
      lastError = nil
      return .succeeded(id: mutationID, operation: operation)
    } catch {
      let message = RuntimePresentation.userFacingError(error)
      if let rpcError = error as? ApplicationServiceRemappingRPCError,
        rpcError.code == .profileUpdateConflict
      {
        lastMutationOperation = operation
        lastMutationID = mutationID
        mutationState = .conflict(profileID: conflictProfileID)
        lastError = message
        return .conflict(id: mutationID, operation: operation)
      }
      lastMutationOperation = operation
      lastMutationID = mutationID
      mutationState = .error(message)
      lastError = message
      return .failed(id: mutationID, operation: operation, message: message)
    }
  }

  func performProfileRecovery(
    request: @escaping @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
  ) async -> String? {
    guard !profileRecoveryInFlight, !mutationInFlight else {
      return OJDLocalized.string(
        "error.operationInProgress",
        fallback: "Another profile operation is already in progress."
      )
    }
    await waitForScopedRefreshCompletion()
    await waitForExclusiveOperationCompletion()
    guard !profileRecoveryInFlight, !mutationInFlight else {
      return OJDLocalized.string(
        "error.operationInProgress",
        fallback: "Another profile operation is already in progress."
      )
    }
    profileRecoveryInFlight = true
    defer {
      profileRecoveryInFlight = false
      resumeExclusiveOperationWaiters()
      schedulePendingScopedRefresh()
    }
    do {
      let snapshot = try await request()
      remappingState = .available(snapshot)
      postEventAccessState = .available(snapshot.postEventAccess)
      authoritativePostEventAccess = snapshot.postEventAccess
      postEventAccessGeneration += 1
      updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
      lastError = nil
      return nil
    } catch {
      let message = RuntimePresentation.userFacingError(error)
      lastError = message
      return message
    }
  }

  @discardableResult
  func rejectMutation(_ request: RuntimeMutationRequest) -> RuntimeMutationResult {
    lastMutationOperation = request.operation
    lastMutationID = request.id
    let message = OJDLocalized.string(
      "error.actionInProgress",
      fallback: "Another profile action is already in progress."
    )
    mutationState = .error(message)
    lastError = message
    return .rejected(id: request.id, operation: request.operation, message: message)
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
