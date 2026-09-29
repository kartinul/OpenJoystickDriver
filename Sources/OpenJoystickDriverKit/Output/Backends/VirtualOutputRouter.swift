import Foundation

/// Routes normalized controller input exclusively to the active virtual HID device.
public final class VirtualOutputRouter: OutputDispatcher, RemappingGamepadSink,
  RemappingGamepadOutputControlling, @unchecked Sendable
{
  private let lock = NSLock()
  private var backend: (any OutputDispatcher)?
  private var _suppressOutput = false
  private var remappingOutputSuppressed = false

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      lock.withLock {
        _suppressOutput = newValue
        backend?.suppressOutput = newValue
      }
    }
  }

  public init() {}

  public func setBackend(_ newBackend: (any OutputDispatcher)?) {
    lock.withLock {
      backend = newBackend
      backend?.suppressOutput = _suppressOutput
    }
  }

  public func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    let target = lock.withLock {
      remappingOutputSuppressed = suppressed
      return backend
    }
    if let controlling = target as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(suppressed)
    }
  }

  public func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
    let target = lock.withLock { remappingOutputSuppressed && state != .neutral ? nil : backend }
    guard let sink = target as? any RemappingGamepadSink else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    if let controlling = target as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(lock.withLock { remappingOutputSuppressed })
    }
    try await sink.send(state, for: identifier)
  }

  public func dispatch(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.dispatch(event, labels: labels, from: identifier)
  }

  public func activateOutput(for identifier: DeviceIdentifier) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.activateOutput(for: identifier)
  }
}

extension VirtualOutputRouter: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: DeviceIdentifier) async {
    let target = lock.withLock { backend }
    if let listener = target as? any ControllerLifecycleListener {
      await listener.controllerDidStop(identifier)
    }
  }
}
