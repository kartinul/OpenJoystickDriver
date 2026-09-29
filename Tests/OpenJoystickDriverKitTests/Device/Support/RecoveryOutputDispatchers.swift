import Foundation

@testable import OpenJoystickDriverKit

actor RecoveryOwnershipGate {
  private(set) var accessDeniedReportStarted = false
  private var isReleased = false
  private var blockedReport: CheckedContinuation<Void, Never>?

  func blockAccessDeniedReport() async {
    accessDeniedReportStarted = true
    guard !isReleased else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      blockedReport = continuation
    }
  }

  func release() {
    isReleased = true
    blockedReport?.resume()
    blockedReport = nil
  }
}

actor RecoveryStopCompletion {
  private(set) var isComplete = false
  func markComplete() { isComplete = true }
}

final class RecoveryGatedOutputDispatcher: OutputDispatcher, ControllerInputOwnershipListener,
  ControllerLifecycleListener, @unchecked Sendable
{
  private let stateLock = NSLock()
  private let gate: RecoveryOwnershipGate
  private var storedOwnershipReports: [HIDInputOwnership] = []
  private var storedDidStopController = false

  var suppressOutput = false
  var ownershipReports: [HIDInputOwnership] { stateLock.withLock { storedOwnershipReports } }
  var didStopController: Bool { stateLock.withLock { storedDidStopController } }

  init(gate: RecoveryOwnershipGate) { self.gate = gate }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}
  func activateOutput(for _: DeviceIdentifier) {}

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) async {
    if ownership == .accessDenied { await gate.blockAccessDeniedReport() }
    stateLock.withLock { storedOwnershipReports.append(ownership) }
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) {
    stateLock.withLock { storedDidStopController = true }
  }
}

final class RecoveryOutputDispatcher: OutputDispatcher, ControllerInputOwnershipListener,
  @unchecked Sendable
{
  private let stateLock = NSLock()
  private var storedOwnershipReports: [HIDInputOwnership] = []
  private var storedDispatchedStates: [ControllerState] = []
  private var storedPresenceCount = 0

  var suppressOutput = false
  /// Activations, which announce a present controller to the virtual output.
  var presenceCount: Int { stateLock.withLock { storedPresenceCount } }
  var ownershipReports: [HIDInputOwnership] { stateLock.withLock { storedOwnershipReports } }
  var dispatchedStates: [ControllerState] { stateLock.withLock { storedDispatchedStates } }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: DeviceIdentifier
  ) { stateLock.withLock { storedDispatchedStates.append(event.state) } }

  func activateOutput(for _: DeviceIdentifier) { stateLock.withLock { storedPresenceCount += 1 } }

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) { stateLock.withLock { storedOwnershipReports.append(ownership) } }
}
