import Foundation
import OpenJoystickDriverKit

final class AutomaticBackendSlot: @unchecked Sendable {
  let backend: any CompatibilityUserSpaceOutputDispatching
  private let lock = NSLock()
  private var leases = 0
  private var retired = false
  private var closed = false
  private var closeCompleted = false
  private var nativeCloseTask: Task<Void, Never>?
  private var retirementWaiters: [CheckedContinuation<Void, Never>] = []
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []

  init(_ backend: any CompatibilityUserSpaceOutputDispatching) { self.backend = backend }

  func acquire() -> AutomaticBackendLease? {
    lock.withLock {
      guard !retired && !closed else { return nil }
      leases += 1
      return AutomaticBackendLease(self)
    }
  }

  /// Revoke admission immediately. A stalled native close must not block other controllers.
  @discardableResult
  func retireAndWait() async -> Bool {
    let shouldClose = lock.withLock {
      retired = true
      return leases == 0
    }
    if shouldClose {
      await closeOnce()
      return true
    }
    do {
      try await withCompatibilityTimeout(
        CompatibilityTransitionTimeouts.standard.candidateCloseNanoseconds,
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
    let shouldClose = lock.withLock { () -> Bool in
      leases -= 1
      return retired && leases == 0 && !closed
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
    lock.withLock {
      if let nativeCloseTask { return nativeCloseTask }
      closed = true
      let task = Task { [backend, weak self] in
        await backend.close()
        let waiters =
          self?.lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            self?.closeCompleted = true
            let result = (self?.retirementWaiters ?? []) + (self?.closeWaiters ?? [])
            self?.retirementWaiters.removeAll()
            self?.closeWaiters.removeAll()
            return result
          } ?? []
        waiters.forEach { $0.resume() }
      }
      nativeCloseTask = task
      return task
    }
  }

  func waitForCloseCompletion() async {
    await withCheckedContinuation { continuation in
      let complete = lock.withLock { () -> Bool in
        if closeCompleted { return true }
        closeWaiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }
}

final class AutomaticBackendLease: @unchecked Sendable {
  private let slot: AutomaticBackendSlot
  private let lock = NSLock()
  private var released = false

  init(_ slot: AutomaticBackendSlot) { self.slot = slot }

  var backend: any CompatibilityUserSpaceOutputDispatching { slot.backend }

  func release() async {
    let shouldRelease = lock.withLock {
      guard !released else { return false }
      released = true
      return true
    }
    if shouldRelease { await slot.release() }
  }
}
