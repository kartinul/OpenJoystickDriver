import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DevicePipelineSleepTests {
  /// The analog-only scripted trigger also gets its normalization-derived trigger button.
  @Test(arguments: [
    (UInt8(3), [InputChange.leftStick(x: 0.8, y: 0)]), (UInt8(4), [.press(.faceEast)]),
    (UInt8(6), [.hat(.north)]), (UInt8(7), [.leftTrigger(0.75), .press(.leftTriggerButton)]),
  ])
  func testIdlePipelineForwardsTheFirstWakeInput(code: UInt8, expected: [InputChange]) async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000,
      idleMonitorIntervalNanoseconds: 10_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([2]))

    try? await Task.sleep(nanoseconds: 80_000_000)

    await pipeline.feedHIDData(Data([code]))

    #expect(
      dispatcher.states == [
        snapshot(.press(.faceSouth)), .neutral, ControllerState.neutral.applying(expected),
      ]
    )
  }

  @Test
  func testForegroundGateNeutralizesOutputAndWaitsForNeutralBeforeResuming() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.states == [snapshot(.press(.faceSouth))])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.states == [snapshot(.press(.faceSouth)), .neutral])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([2]))
    #expect(dispatcher.states == [snapshot(.press(.faceSouth)), .neutral])

    await pipeline.feedHIDData(Data([4]))
    #expect(
      dispatcher.states == [snapshot(.press(.faceSouth)), .neutral, snapshot(.press(.faceEast))]
    )
  }

  @Test
  func testForegroundGateRearmsAfterFirstPostFocusChangeWithoutFullNeutral() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([3]))
    #expect(dispatcher.states == [snapshot(.leftStick(x: 0.8, y: 0))])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.states == [snapshot(.leftStick(x: 0.8, y: 0)), .neutral])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([5]))
    #expect(dispatcher.states == [snapshot(.leftStick(x: 0.8, y: 0)), .neutral])

    await pipeline.feedHIDData(Data([4]))
    // The stick held across the gate stays hidden until it changes.
    #expect(
      dispatcher.states == [
        snapshot(.leftStick(x: 0.8, y: 0)), .neutral, snapshot(.press(.faceEast)),
      ]
    )
  }

  @Test
  func testRepeatedAllowedSignalDoesNotRearmForegroundGate() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([4]))

    #expect(dispatcher.states == [snapshot(.press(.faceEast))])
  }

  @Test
  func testPipelineSkipsSnapshotsThatDoNotChangeTheDispatchedState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([9]))
    await pipeline.feedHIDData(Data([11]))
    #expect(dispatcher.states.isEmpty)

    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([10]))
    #expect(dispatcher.states == [snapshot(.press(.faceSouth))])
  }

  @Test
  func testStopNeutralizesForwardedButtonState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.stop()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(dispatcher.states == [snapshot(.press(.faceSouth)), .neutral])
  }

  @Test
  func testStopNeutralizesForwardedDpadAndAxesState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([6]))
    await pipeline.feedHIDData(Data([3]))
    await pipeline.stop()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(
      dispatcher.states == [
        snapshot(.hat(.north)), snapshot(.hat(.north), .leftStick(x: 0.8, y: 0)), .neutral,
      ]
    )
  }

  @Test
  func testReconnectDoesNotKeepAForegroundMaskFromTheEndedConnection() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 10462, productID: 4418),
      transport: .hid(locationID: 1),
      driver: ScriptedLifecycleInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([7]))
    await pipeline.feedHIDData(Data([1]))
    // Lifting the gate with South held masks it until it changes.
    await pipeline.setExternalOutputAllowed(false)
    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([8]))
    await pipeline.feedHIDData(Data([7]))
    await pipeline.feedHIDData(Data([1]))

    // The reconnected controller's first press is visible; the old connection's mask is gone.
    #expect(dispatcher.states.last == snapshot(.press(.faceSouth)))
    await pipeline.stop()
  }

  @Test
  func testInputConnectionLifecycleDefersAndStopsOutput() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 10462, productID: 4418),
      transport: .hid(locationID: 1),
      driver: ScriptedLifecycleInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    #expect(await pipeline.hidDeactivationWrites().isEmpty)

    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.states.isEmpty)

    let connectReports = await pipeline.feedHIDData(Data([7]))
    #expect(dispatcher.activations == 1 && dispatcher.states.isEmpty)
    #expect(connectReports == [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xAA]))])

    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.states == [snapshot(.press(.faceSouth))])
    let shutdownReports = await pipeline.hidDeactivationWrites()
    #expect(shutdownReports == [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB]))])

    let disconnectReports = await pipeline.feedHIDData(Data([8]))
    #expect(dispatcher.states == [snapshot(.press(.faceSouth)), .neutral])
    #expect(disconnectReports == [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB]))])
    #expect(await pipeline.hidDeactivationWrites().isEmpty)
    #expect(dispatcher.stoppedIdentifiers == [DeviceIdentifier(vendorID: 10462, productID: 4418)])
  }

}

private final class ScriptedInputParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  private var script = ScriptedState()
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let changes: [InputChange]
    switch data.first {
    case 1: changes = [.press(.faceSouth)]
    case 2: changes = [.release(.faceSouth)]
    case 3: changes = [.leftStick(x: 0.8, y: 0)]
    case 4: changes = [.press(.faceEast)]
    case 5: changes = [.leftStick(x: 0.6, y: 0)]
    case 6: changes = [.hat(.north)]
    case 7: changes = [.leftTrigger(0.75)]
    case 9: changes = [.press(.faceSouth), .release(.faceSouth)]
    case 10: changes = [.press(.faceSouth), .press(.faceSouth)]
    case 11: changes = [.leftStick(x: .nan, y: .infinity)]
    default: return nil
    }
    return script.event(changes, at: receivedAt)
  }
}

private final class ScriptedLifecycleInputParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan(requiresInputConnectionBeforeOutput: true)
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  private var connected = false
  private var pendingState: ControllerInputConnectionState?
  private var script = ScriptedState()

  func activationWrites() -> [PhysicalOutputWrite] {
    [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xAA]))]
  }

  func deactivationWrites() -> [PhysicalOutputWrite] {
    [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB]))]
  }

  func inputConnectionWrites(for state: ControllerInputConnectionState) -> [PhysicalOutputWrite] {
    state == .connected ? activationWrites() : deactivationWrites()
  }

  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let state = pendingState
    pendingState = nil
    return state
  }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    switch data.first {
    case 7:
      connected = true
      pendingState = .connected
      return nil
    case 8:
      connected = false
      pendingState = .disconnected
      script = ScriptedState()
      return nil
    case 1 where connected: return script.event([.press(.faceSouth)], at: receivedAt)
    default: return nil
    }
  }
}

private final class RecordingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  private let lock = NSLock()
  private var recordedStates: [ControllerState] = []
  private var recordedActivations = 0
  private var recordedStops: [DeviceIdentifier] = []

  var states: [ControllerState] { lock.withLock { recordedStates } }
  var activations: Int { lock.withLock { recordedActivations } }
  var stoppedIdentifiers: [DeviceIdentifier] { lock.withLock { recordedStops } }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: DeviceIdentifier
  ) { lock.withLock { recordedStates.append(event.state) } }

  func activateOutput(for _: DeviceIdentifier) { lock.withLock { recordedActivations += 1 } }
}

extension RecordingOutputDispatcher: ControllerLifecycleListener {
  func controllerDidStop(_ identifier: DeviceIdentifier) {
    lock.withLock { recordedStops.append(identifier) }
  }
}
