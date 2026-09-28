import Foundation
import OpenJoystickDriverKit

enum CompatibilityTransitionError: Error, Sendable {
  case stageTimedOut
  case feedbackTimedOut
  case candidateCloseTimedOut
  case activationTimedOut
}

func withCompatibilityTimeout<Value: Sendable>(
  _ timeout: UInt64,
  clock: CompatibilityTransitionClock,
  error: CompatibilityTransitionError,
  operation: @escaping @Sendable () async throws -> Value,
  onLateSuccess: @escaping @Sendable (Value) async -> Void = { _ in }
) async throws -> Value {
  guard timeout > 0 else { throw error }

  let stream = AsyncThrowingStream<Value, Error> { continuation in
    let operationTask = Task.detached {
      do {
        let result = try await operation()
        switch continuation.yield(result) {
        case .enqueued: continuation.finish()
        case .dropped, .terminated:
          await onLateSuccess(result)
          continuation.finish()
        @unknown default: continuation.finish()
        }
      } catch { continuation.finish(throwing: error) }
    }
    let timerTask = Task.detached {
      do {
        try await clock.sleep(timeout)
        continuation.finish(throwing: error)
      } catch {
        // Cancellation only stops the timer.
      }
    }
    continuation.onTermination = { _ in
      operationTask.cancel()
      timerTask.cancel()
    }
  }
  var iterator = stream.makeAsyncIterator()
  guard let result = try await iterator.next() else { throw CancellationError() }
  return result
}

final class CompatibilityTransitionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false

  var isStopped: Bool { lock.withLock { stopped } }
  func stop() { lock.withLock { stopped = true } }
}

actor CompatibilityTransitionCoordinator {
  private var tail: Task<Void, Never>?
  private let cancellation = CompatibilityTransitionCancellation()

  func enqueue(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
    await enqueueResult(operation) ?? false
  }

  /// Runs `operation` after every earlier operation; nil when the coordinator stops first.
  func enqueueResult<Value: Sendable>(
    _ operation: @escaping @Sendable () async -> Value
  ) async -> Value? {
    guard !cancellation.isStopped else { return nil }
    let previous = tail
    let cancellation = self.cancellation
    let next = Task<Value?, Never> {
      await previous?.value
      guard !Task.isCancelled, !cancellation.isStopped else { return nil }
      return await operation()
    }
    tail = Task {
      await withTaskCancellationHandler {
        _ = await next.value
      } onCancel: {
        next.cancel()
      }
    }
    return await next.value
  }

  func stop() {
    cancellation.stop()
    tail?.cancel()
    tail = nil
  }
}

final class CompatibilityFeedbackGate: @unchecked Sendable {
  typealias SendFeedback = @Sendable (DeviceIdentifier, ControllerOutputCommand) async -> Void

  private let sendFeedback: SendFeedback
  let lock = NSLock()
  private var accepting = true
  private var generation: UInt64 = 0
  private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]

  init(deviceManager: DeviceManager) {
    sendFeedback = { identifier, command in
      guard let command = Self.physicalFeedback(for: command) else { return }
      _ = await deviceManager.sendControllerOutput(command, for: identifier)
    }
  }

  init(sendFeedback: @escaping SendFeedback) { self.sendFeedback = sendFeedback }

  /// The physical command for consumer feedback: a bounded set-rumble, with its main motors
  /// mirrored onto the Steam trackpad haptics, or stop-rumble. Other consumer commands, such as a
  /// DualSense lightbar, and held rumble do not reach the physical controller.
  static func physicalFeedback(for command: ControllerOutputCommand) -> ControllerOutputCommand? {
    switch command {
    case .setRumble(let intensities, .milliseconds(let durationMs)):
      .setRumble(intensities.mirroringMainOntoHaptics(), duration: .milliseconds(durationMs))
    case .stopRumble: .stopRumble
    default: nil
    }
  }

  func submit(identifier: DeviceIdentifier, command: ControllerOutputCommand) {
    let token = UUID()
    let currentGeneration = lock.withLock { () -> UInt64? in
      guard accepting else { return nil }
      return generation
    }
    guard let currentGeneration else { return }
    let task = Task { [weak self] in
      guard let self, self.isCurrent(currentGeneration) else {
        self?.finish(token)
        return
      }
      await self.sendFeedback(identifier, command)
      self.finish(token)
    }
    let shouldCancel = lock.withLock { () -> Bool in
      cancellationHandlers[token] = { task.cancel() }
      return !accepting || generation != currentGeneration
    }
    if shouldCancel { task.cancel() }
  }

  func quiesceAndNeutralize(
    _ identifiers: [DeviceIdentifier],
    timeout: UInt64 = CompatibilityTransitionTimeouts.standard.feedbackNanoseconds,
    clock: CompatibilityTransitionClock = .system,
    resumeWhenComplete: Bool = false
  ) async -> Bool {
    let (wasAccepting, cancellations) = lock.withLock {
      let wasAccepting = accepting
      accepting = false
      generation &+= 1
      let cancellations = Array(cancellationHandlers.values)
      cancellationHandlers.removeAll()
      return (wasAccepting, cancellations)
    }
    cancellations.forEach { $0() }

    // A canceled HID/USB write is not required to cooperate with Swift task cancellation. Once
    // admission advances to a new generation, quarantine those writes instead of waiting for
    // their completion. Queue one neutral write per controller behind any late operation and
    // bound only how long this transition waits for the neutralization attempt.
    do {
      try await withCompatibilityTimeout(timeout, clock: clock, error: .feedbackTimedOut) {
        await withTaskGroup(of: Void.self) { group in
          for identifier in identifiers {
            group.addTask { await self.sendFeedback(identifier, .stopRumble) }
          }
          await group.waitForAll()
        }
      }
    } catch {
      // The queued neutral writes remain owned by their transport workers. Their late completion
      // cannot re-open feedback admission or mutate the compatibility publication.
    }
    if resumeWhenComplete && wasAccepting { resume() }
    return true
  }

  func resume() {
    lock.withLock {
      generation &+= 1
      accepting = true
    }
  }

  private func isCurrent(_ generation: UInt64) -> Bool {
    lock.withLock { accepting && self.generation == generation }
  }

  private func finish(_ token: UUID) {
    _ = lock.withLock { cancellationHandlers.removeValue(forKey: token) }
  }
}

final class CompatibilityBackendCloseSlot: @unchecked Sendable {
  let backend: any CompatibilityUserSpaceOutputDispatching
  let lock = NSLock()
  private var closeTask: Task<Void, Never>?

  init(_ backend: any CompatibilityUserSpaceOutputDispatching) { self.backend = backend }

  func close(timeout: UInt64, clock: CompatibilityTransitionClock) async -> Bool {
    let task = lock.withLock { () -> Task<Void, Never> in
      if let closeTask { return closeTask }
      let backend = self.backend
      let task = Task.detached { await backend.close() }
      closeTask = task
      return task
    }
    do {
      try await withCompatibilityTimeout(timeout, clock: clock, error: .candidateCloseTimedOut) {
        await task.value
      }
      return true
    } catch { return false }
  }
}
