import Foundation

@testable import OpenJoystickDriverKit

/// Records every event batch with the controller that dispatched it.
final class HIDRoleEventRecorder: OutputDispatcher, @unchecked Sendable {
  private let lock = NSLock()
  private var dispatched: [(DeviceIdentifier, ControllerState)] = []
  private var suppressed = false

  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) { lock.withLock { dispatched.append((identifier, event.state)) } }

  func activateOutput(for _: DeviceIdentifier) {}

  /// Controls pressed in any state dispatched from `identifier`.
  func pressed(from identifier: DeviceIdentifier) -> Set<ControlID> {
    lock.withLock {
      dispatched.filter { $0.0 == identifier }.reduce(into: []) { $0.formUnion($1.1.pressed) }
    }
  }
}
