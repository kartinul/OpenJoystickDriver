import Foundation

/// Common interface for virtual HID profile outputs.
public protocol VirtualOutputDispatching: OutputDispatcher {
  /// Backend status for UI and CLI reporting.
  var status: VirtualOutputBackendStatus { get }
  /// Most recent app-originated rumble report summary, or `nil` before any rumble report.
  var lastRumbleStatus: String? { get }
  /// Forces creation and neutral activation of every supplied virtual device.
  func activate(for identifiers: [DeviceIdentifier]) async throws
  /// Updates suppression and waits for any required output barrier.
  func setOutputSuppressed(_ suppressed: Bool) async
  /// Drains and tears down user-space virtual HID devices owned by this output.
  func close() async
  /// Delivers input while preserving publication failures for recovery coordinators.
  func dispatchReportingFailure(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async throws
  /// Activates output for one controller while preserving publication failures.
  func activateOutputReportingFailure(for identifier: DeviceIdentifier) async throws
}

/// Optional activation surface used to enforce a deadline for each controller in a set.
public protocol VirtualOutputControllerActivating: AnyObject, Sendable {
  func activate(controller identifier: DeviceIdentifier) async throws
}

/// Optional output-dispatcher hook for controller lifecycle events.
///
/// `DevicePipeline` calls this when a physical controller pipeline stops so output backends
/// can tear down any per-controller virtual devices.
public protocol ControllerLifecycleListener: AnyObject, Sendable {
  func controllerDidStop(_ identifier: DeviceIdentifier) async
}

/// Receives physical input ownership before controller input or virtual activation is admitted.
public protocol ControllerInputOwnershipListener: AnyObject, Sendable {
  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) async
}

extension VirtualOutputDispatching {
  public func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
  public func dispatchReportingFailure(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async throws { await dispatch(event, labels: labels, from: identifier) }
  public func activateOutputReportingFailure(for identifier: DeviceIdentifier) async throws {
    await activateOutput(for: identifier)
  }
}

/// Tells an observe-only pipeline whether any consumer uses its controller's input, so a native
/// gamepad with no remapping costs no per-report dispatch. The answer follows route changes, so
/// a profile selected later takes effect without reconnecting.
public protocol ObservedInputDemand: AnyObject, Sendable {
  func wantsObservedInput(from identifier: DeviceIdentifier) -> Bool
}

/// Takes controller state snapshots and sends them to an output target.
///
/// Implement this inward-owned port to decide what happens when controller state changes.
/// Production adapters live in their owning transport targets; the kit provides
/// ``LoggingOutputDispatcher`` for diagnostics.
public protocol OutputDispatcher: AnyObject, Sendable {
  /// When `true`, all report/event output is suppressed (e.g. during developer
  /// packet capture). Implementations should invalidate any cached state on change.
  var suppressOutput: Bool { get set }
  func setOutputSuppressed(_ suppressed: Bool) async

  /// Receives one controller's full state and writes it to the output.
  ///
  /// Called by ``DevicePipeline`` when the state changes or a report carries samples, and again
  /// with an unchanged state to activate output for the controller.
  /// - Parameters:
  ///   - event: The controller's state and the samples of the report that produced it.
  ///   - labels: The family labels the controller's pipeline was bound with; the same source
  ///     always passes the same labels.
  ///   - identifier: Which controller the state came from.
  func dispatch(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async

  /// Ensures output exists for the controller, for example a virtual device, without new input.
  ///
  /// Called by the pipeline and discovery once a controller's session can publish, and again
  /// after it resumes or reconnects.
  func activateOutput(for identifier: DeviceIdentifier) async
}

extension OutputDispatcher {
  public func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
}

/// OutputDispatcher that logs controller events to debug output.
///
/// Used for hardware validation and testing. Production output uses a transport adapter.
public final class LoggingOutputDispatcher: OutputDispatcher, Sendable {
  // Suppression is ignored because this dispatcher is only for development.
  /// Accepted but ignored; this dispatcher always logs.
  private let storedSuppression = Locked(false)
  public var suppressOutput: Bool {
    get { storedSuppression.withLock { $0 } }
    set { storedSuppression.withLock { $0 = newValue } }
  }

  /// Creates a new LoggingOutputDispatcher.
  public init() {}

  /// Prints each state to standard output.
  public func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) {
    print(
      "[Output] "
        + "\(identifier.controllerIdentity.vendorID):\(identifier.controllerIdentity.productID)"
        + " -> \(event.state)"
    )
  }

  /// Nothing to activate: this dispatcher only logs.
  public func activateOutput(for _: DeviceIdentifier) {}
}
