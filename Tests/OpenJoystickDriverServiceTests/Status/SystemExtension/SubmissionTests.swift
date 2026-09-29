import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct SubmissionTests {
  @Test
  func submissionCompletionIsOneShotAcrossTerminalEvents() {
    let gate = SystemExtensionSubmissionCompletionGate()

    #expect(gate.accept())
    #expect(!gate.accept())
    #expect(!gate.accept())
  }

  @Test
  func submissionCompletionGateWinsConcurrentRaces() async {
    let gate = SystemExtensionSubmissionCompletionGate()
    let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
      for _ in 0..<100 { group.addTask { gate.accept() } }
      var count = 0
      for await result in group where result { count += 1 }
      return count
    }

    #expect(accepted == 1)
  }

  @Test
  func cancellationBeforeStartPreventsSubmission() {
    let state = SystemExtensionRequestState()
    let submission = FakeSubmission()

    state.cancel()

    #expect(!state.start(submission))
    #expect(submission.startCount == 0)
    #expect(submission.cancelCount == 0)
  }

  @Test
  func actualSubmissionBoundaryCompletesOnceUnderConcurrentRaces() async {
    let counter = LockedCount()
    let submission = SystemExtensionSubmission(mode: .activation) { _ in counter.increment() }

    await withTaskGroup(of: Void.self) { group in
      group.addTask { submission.cancel() }
      group.addTask { submission.timeout() }
      group.addTask { submission.completeForTesting(.active) }
    }

    #expect(counter.value == 1)
  }
}

private final class FakeSubmission: SystemExtensionSubmissionControlling, @unchecked Sendable {
  private(set) var startCount = 0
  private(set) var cancelCount = 0

  func start() { startCount += 1 }
  func cancel() { cancelCount += 1 }
}

private final class LockedCount: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}
