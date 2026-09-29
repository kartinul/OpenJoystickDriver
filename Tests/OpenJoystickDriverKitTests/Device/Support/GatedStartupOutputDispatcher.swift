import Foundation

@testable import OpenJoystickDriverKit

actor StartupTestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in self.continuation = continuation }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}

final class GatedStartupOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  private let lock = NSLock()
  private let firstDispatchStarted = StartupTestGate()
  private let releaseFirstDispatch = StartupTestGate()
  private var blockFirstEmptyBatch = true
  private var storedSuppression = false

  var suppressOutput: Bool {
    get { lock.withLock { storedSuppression } }
    set { lock.withLock { storedSuppression = newValue } }
  }

  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}

  /// Blocks the first activation until released.
  func activateOutput(for _: DeviceIdentifier) async {
    let shouldBlock = lock.withLock { () -> Bool in
      guard blockFirstEmptyBatch else { return false }
      blockFirstEmptyBatch = false
      return true
    }
    guard shouldBlock else { return }
    await firstDispatchStarted.open()
    await releaseFirstDispatch.wait()
  }

  func waitForBlockedDispatch() async { await firstDispatchStarted.wait() }

  func releaseBlockedDispatch() async { await releaseFirstDispatch.open() }
}
