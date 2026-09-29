import Foundation
import OpenJoystickDriverKit

final class AutomaticBackendSlot: Sendable {
  private struct State {
    var leases = 0
    var retired = false
    var closed = false
    var closeCompleted = false
    var nativeCloseTask: Task<Void, Never>?
    var retirementWaiters: [CheckedContinuation<Void, Never>] = []
    var closeWaiters: [CheckedContinuation<Void, Never>] = []
  }

  let backend: any VirtualOutputDispatching
  private let state = Locked(State())

  init(_ backend: any VirtualOutputDispatching) { self.backend = backend }

  func acquire() -> AutomaticBackendLease? {
    state.withLock { state in
      guard !state.retired && !state.closed else { return nil }
      state.leases += 1
      return AutomaticBackendLease(self)
    }
  }

  /// Revoke admission immediately. A stalled native close must not block other controllers.
  @discardableResult
  func retireAndWait() async -> Bool {
    let shouldClose = state.withLock { state in
      state.retired = true
      return state.leases == 0
    }
    if shouldClose {
      await closeOnce()
      return true
    }
    do {
      try await withVirtualOutputTimeout(
        VirtualOutputTransitionTimeouts.standard.candidateCloseNanoseconds,
        clock: .system,
        error: .candidateCloseTimedOut
      ) { [self] in await waitForCloseCompletion() }
      return true
    } catch {
      _ = beginClose()
      return false
    }
  }

  func release() async {
    let shouldClose = state.withLock { state -> Bool in
      state.leases -= 1
      return state.retired && state.leases == 0 && !state.closed
    }
    if shouldClose { await closeOnce() }
  }

  func closeOnce() async {
    let task = beginClose()
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  @discardableResult
  private func beginClose() -> Task<Void, Never> {
    let backend = self.backend
    return state.withLock { state in
      if let nativeCloseTask = state.nativeCloseTask { return nativeCloseTask }
      state.closed = true
      let task = Task { [weak self] in
        await backend.close()
        let waiters =
          self?.state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.closeCompleted = true
            let result = state.retirementWaiters + state.closeWaiters
            state.retirementWaiters.removeAll()
            state.closeWaiters.removeAll()
            return result
          } ?? []
        waiters.forEach { $0.resume() }
      }
      state.nativeCloseTask = task
      return task
    }
  }

  func waitForCloseCompletion() async {
    await withCheckedContinuation { continuation in
      let complete = state.withLock { state -> Bool in
        if state.closeCompleted { return true }
        state.closeWaiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }
}

final class AutomaticBackendLease: Sendable {
  private let slot: AutomaticBackendSlot
  private let released = Locked(false)

  init(_ slot: AutomaticBackendSlot) { self.slot = slot }

  var backend: any VirtualOutputDispatching { slot.backend }

  func release() async {
    let shouldRelease = released.withLock { released in
      guard !released else { return false }
      released = true
      return true
    }
    if shouldRelease { await slot.release() }
  }
}
