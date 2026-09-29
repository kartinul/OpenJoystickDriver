import Foundation

@testable import OpenJoystickDriverKit

/// Records every event batch a controller pipeline dispatches, and answers observed-input demand.
final class NativeEventRecorder: OutputDispatcher, ObservedInputDemand, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [ControllerState] = []
  private var suppressed = false
  private var demanded = true

  var states: [ControllerState] { lock.withLock { recorded } }
  var demandsInput: Bool {
    get { lock.withLock { demanded } }
    set { lock.withLock { demanded = newValue } }
  }

  func wantsObservedInput(from _: DeviceIdentifier) -> Bool { demandsInput }
  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: DeviceIdentifier
  ) { lock.withLock { recorded.append(event.state) } }

  func activateOutput(for _: DeviceIdentifier) {}
}
