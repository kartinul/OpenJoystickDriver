import Foundation
import Testing

@testable import OpenJoystickDriverKit

actor UserSpaceDispatcherTestGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waiting = false

  func wait() async {
    if isOpen { return }
    waiting = true
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async { while !waiting && !isOpen { await Task.yield() } }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

final class UserSpaceDispatcherTestBackend: UserSpaceOutputDispatcher.VirtualDeviceBackend,
  @unchecked Sendable
{
  struct SendFailure: Error, Sendable {}

  private let lock = NSLock()
  private var closed = false
  private(set) var closeCount = 0
  private(set) var sendCount = 0
  private var reports: [[UInt8]] = []
  let sendGate: UserSpaceDispatcherTestGate?
  let failsSend: Bool

  init(sendGate: UserSpaceDispatcherTestGate? = nil, failsSend: Bool = false) {
    self.sendGate = sendGate
    self.failsSend = failsSend
  }

  func send(_ report: [UInt8]) async throws {
    await sendGate?.wait()
    if failsSend { throw SendFailure() }
    guard lock.withLock({ !closed }) else { return }
    lock.withLock {
      sendCount += 1
      reports.append(report)
    }
  }

  func close() {
    lock.withLock {
      guard !closed else { return }
      closed = true
      closeCount += 1
    }
  }

  func counts() -> (close: Int, send: Int) { lock.withLock { (closeCount, sendCount) } }
  func publishedReports() -> [[UInt8]] { lock.withLock { reports } }
}

struct ContinuitySnapshotReportFormat: VirtualGamepadReportFormat {
  let descriptor: [UInt8] = []
  let inputReportPayloadSize = 19
  let inputReportID: UInt8? = nil

  func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var report = [
      UInt8(truncatingIfNeeded: state.buttons), UInt8(truncatingIfNeeded: state.buttons >> 8),
      UInt8(truncatingIfNeeded: state.buttons >> 16),
      UInt8(truncatingIfNeeded: state.buttons >> 24),
    ]
    for value in [
      state.leftStickX, state.leftStickY, state.rightStickX, state.rightStickY, state.leftTrigger,
      state.rightTrigger,
    ] {
      report.append(UInt8(truncatingIfNeeded: value))
      report.append(UInt8(truncatingIfNeeded: value >> 8))
    }
    report.append(state.leftTriggerPressed ? 1 : 0)
    report.append(state.rightTriggerPressed ? 1 : 0)
    report.append(state.hat.rawValue)
    return report
  }
}

enum ExpectedButtonOutput {
  case bit(Int)
  case leftTrigger
  case rightTrigger
}

struct UserSpaceOutputDispatcherLifecycleTests {}

final class LockedBackends: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UserSpaceDispatcherTestBackend] = []

  func append(_ backend: UserSpaceDispatcherTestBackend) {
    lock.withLock { values.append(backend) }
  }

  func snapshot() -> [UserSpaceDispatcherTestBackend] { lock.withLock { values } }
}

final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }

  func current() -> Int { lock.withLock { value } }
}
