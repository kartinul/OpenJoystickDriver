import Foundation

@testable import OpenJoystickDriverKit

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

final class LockedBackends: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UserSpaceDispatcherTestBackend] = []

  func append(_ backend: UserSpaceDispatcherTestBackend) {
    lock.withLock { values.append(backend) }
  }

  func snapshot() -> [UserSpaceDispatcherTestBackend] { lock.withLock { values } }
}
