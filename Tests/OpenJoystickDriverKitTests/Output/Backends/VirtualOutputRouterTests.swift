import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualOutputRouterTests {
  @Test
  func dispatchesOnlyToCurrentVirtualOutputBackend() async {
    let previous = RecordingVirtualOutputDispatcher()
    let current = RecordingVirtualOutputDispatcher()
    let dispatcher = VirtualOutputRouter()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    dispatcher.setBackend(previous)
    dispatcher.setBackend(current)
    await dispatcher.dispatch(
      ControllerEvent([.press(.faceSouth)]),
      labels: .playStation,
      from: identifier
    )
    await dispatcher.activateOutput(for: identifier)

    #expect(previous.states.isEmpty && previous.activations.isEmpty)
    #expect(current.states == [snapshot(.press(.faceSouth))])
    #expect(current.labels == [.playStation])
    #expect(current.activations == [identifier])
  }

  @Test
  func explicitSuppressionStopsVirtualOutputDispatch() async {
    let backend = RecordingVirtualOutputDispatcher()
    let dispatcher = VirtualOutputRouter()
    dispatcher.setBackend(backend)
    dispatcher.suppressOutput = true

    await dispatcher.dispatch(
      ControllerEvent([.press(.faceSouth)]),
      labels: .standard,
      from: DeviceIdentifier(vendorID: 1, productID: 2)
    )
    await dispatcher.activateOutput(for: DeviceIdentifier(vendorID: 1, productID: 2))

    #expect(backend.states.isEmpty && backend.activations.isEmpty)
    #expect(backend.suppressOutput)
  }
}

private final class RecordingVirtualOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private let lock = NSLock()
  private var recorded: [(ControllerState, ControllerButtonLabels)] = []
  private var recordedActivations: [DeviceIdentifier] = []

  var states: [ControllerState] { lock.withLock { recorded.map(\.0) } }
  var labels: [ControllerButtonLabels] { lock.withLock { recorded.map(\.1) } }
  var activations: [DeviceIdentifier] { lock.withLock { recordedActivations } }

  func dispatch(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from _: DeviceIdentifier
  ) async {
    await Task.yield()
    lock.withLock { recorded.append((event.state, labels)) }
  }

  func activateOutput(for identifier: DeviceIdentifier) {
    lock.withLock { recordedActivations.append(identifier) }
  }
}
