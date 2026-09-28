import Combine
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

extension InputTestTests {
  @Test
  @MainActor
  func calibrationSelectionFollowsDisconnectAndClose() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    let device = makeInputTestDevice()
    model.selectDevice(device)
    #expect(model.motionCalibration.selector == RuntimeDeviceSelector(device: device))
    model.reconcileConnectedDevices([])
    #expect(model.motionCalibration.selector == nil)
    model.reconcileConnectedDevices([device])
    #expect(model.motionCalibration.selector == RuntimeDeviceSelector(device: device))
    model.close()
    #expect(model.motionCalibration.selector == nil)
  }

  @Test
  @MainActor
  func openingStartsSamplingImmediately() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)

    model.selectDevice(makeInputTestDevice())
    model.open()
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().input > 0)
    model.close()
  }

  @Test
  @MainActor
  func closeCancelsTheActiveLookup() async {
    var first = ControllerState.neutral
    first.pressed = [.faceSouth]
    let gateway = InputTestGatewayStub(inputSequence: [first], inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    var deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await gateway.counts().input == 0, ContinuousClock.now < deadline {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().input == 1)

    model.close()
    deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await gateway.counts().cancelled == 0, ContinuousClock.now < deadline {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(model.sessionState == .idle)
    #expect(await gateway.counts().cancelled == 1)
    #expect(await gateway.counts().input == 1)
  }

  @Test
  @MainActor
  func liveSamplingPublishesNormalizedState() async {
    var pressed = ControllerState.neutral
    pressed.pressed = [.faceSouth]
    pressed.hat = .north
    pressed.leftStick.x = BipolarValue(normalized: 0.75)
    pressed.rightTrigger = UnipolarValue(normalized: 0.5)
    let gateway = InputTestGatewayStub(inputSequence: [pressed])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.latestInput != pressed, ContinuousClock.now < deadline {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(model.sessionState == .live)
    #expect(model.latestInput == pressed)
    #expect(await gateway.inputSelectors == [RuntimeDeviceSelector(device: makeInputTestDevice())])
    model.close()
  }

  @Test
  @MainActor
  func unchangedSnapshotsDoNotRepublishInputState() async {
    let snapshot = ControllerState.neutral
    let gateway = InputTestGatewayStub(
      inputSequence: Array(repeating: snapshot, count: 4),
      inputDelayNanoseconds: 1_000_000
    )
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())
    var publishedSnapshots = 0
    let observation = model.liveState.$snapshot.dropFirst().sink { _ in publishedSnapshots += 1 }

    model.open()
    let receivedAllSnapshots = await gateway.waitForInputCalls(4)
    model.close()

    #expect(receivedAllSnapshots)
    #expect(publishedSnapshots == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func liveInputUpdatesDoNotInvalidateTheSessionAndOutputModel() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    var broadInvalidations = 0
    let observation = model.objectWillChange.sink { broadInvalidations += 1 }
    var snapshot = model.latestInput
    snapshot.leftStick.x = BipolarValue(normalized: 0.75)
    snapshot.pressed = [.faceSouth]

    model.liveState.update(snapshot)

    #expect(model.latestInput == snapshot)
    #expect(broadInvalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func outputControlChangesDoNotInvalidateTheSessionModel() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    var broadInvalidations = 0
    let observation = model.objectWillChange.sink { broadInvalidations += 1 }

    model.rumbleDurationMilliseconds = 750
    model.rumbleIntensities[.leftMain] = 128
    model.brightness = 192

    #expect(broadInvalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func repeatedUnavailableSamplesStopTheLoopWithoutUnboundedRetry() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    await waitUntil { model.sessionState == .unavailable }
    let callsAtStop = await gateway.counts().input
    try? await Task.sleep(nanoseconds: 5_000_000)

    #expect(model.sessionState == .unavailable)
    #expect(callsAtStop == 3)
    #expect(await gateway.counts().input == callsAtStop)
  }

  @Test
  @MainActor
  func statusRefreshRecoversAStoppedAutomaticSession() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    let device = makeInputTestDevice()
    model.selectDevice(device)
    model.open()
    await waitUntil { model.sessionState == .unavailable }

    model.reconcileConnectedDevices([device])

    #expect(await gateway.waitForInputCalls(4))
    model.close()
  }

  @Test
  @MainActor
  func repeatedOpenAndStatusUpdatesKeepOneSamplingTask() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice()
    model.selectDevice(device)

    model.open()
    model.open()
    model.reconcileConnectedDevices([device])
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(await gateway.counts().input == 1)
    #expect(await gateway.counts().maximumConcurrentInput == 1)
    model.close()
  }

  @Test
  @MainActor
  func repeatedFailuresRetainTheLastSnapshotAndFinishStale() async {
    var snapshot = ControllerState.neutral
    snapshot.pressed = [.faceSouth]
    let gateway = InputTestGatewayStub(inputSequence: [snapshot])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    // One live sample then three nils stops the loop. Wait for all four requests
    // because `.stale` is also the transient state after the first nil.
    #expect(await gateway.waitForInputCalls(4))

    #expect(model.sessionState == .stale)
    #expect(model.latestInput == snapshot)
    #expect(await gateway.counts().input == 4)
    #expect(!model.isSampling)
  }

  @Test
  @MainActor
  func samplingNeverOverlapsInputRequests() async {
    let snapshot = ControllerState.neutral
    let gateway = InputTestGatewayStub(
      inputSequence: Array(repeating: snapshot, count: 8),
      inputDelayNanoseconds: 5_000_000
    )
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    #expect(await gateway.waitForInputCalls(2))
    model.close()

    #expect(await gateway.counts().input > 1)
    #expect(await gateway.counts().maximumConcurrentInput == 1)
  }

  @Test
  @MainActor
  func switchingDevicesTransfersAutomaticSamplingOwnership() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let oldDevice = makeInputTestDevice(runtimeIdentifier: "input-test-old")
    let newDevice = makeInputTestDevice(runtimeIdentifier: "input-test-new")
    model.selectDevice(oldDevice)
    model.open()
    try? await Task.sleep(nanoseconds: 20_000_000)

    model.selectDevice(newDevice)
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.device?.runtimeIdentifier == newDevice.runtimeIdentifier)
    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().cancelled == 1)
    #expect(
      await gateway.inputSelectors == [
        RuntimeDeviceSelector(device: oldDevice), RuntimeDeviceSelector(device: newDevice),
      ]
    )
    model.close()
  }

  @Test
  @MainActor
  func unsupportedOutputControlsNeverDispatch() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: .none))

    model.testRumble()
    model.applyPlayerIndicator()
    model.applyColor()
    model.applyBrightness()
    try? await Task.sleep(nanoseconds: 10_000_000)

    let counts = await gateway.counts()
    #expect(counts.rumble == 0)
    #expect(counts.player == 0)
    #expect(counts.color == 0)
    #expect(counts.brightness == 0)
  }

  @Test
  @MainActor
  func rumbleMapsDeclaredMotorsAndBinaryValues() async {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftHaptic, .rightTrigger],
      binaryRumbleMotors: [.rightTrigger]
    )
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(capabilities: capabilities)
    model.selectDevice(device)
    model.rumbleIntensities[.leftHaptic] = 127
    model.rumbleIntensities[.rightTrigger] = 1
    model.rumbleDurationMilliseconds = 100

    model.testRumble()
    try? await Task.sleep(nanoseconds: 30_000_000)

    let calls = await gateway.rumbleCalls
    let active = calls.first {
      $0.left != 0 || $0.right != 0 || $0.leftTrigger != 0 || $0.rightTrigger != 0
    }
    #expect(active?.selector == RuntimeDeviceSelector(device: device))
    #expect(active?.left == 127)
    #expect(active?.right == 0)
    #expect(active?.leftTrigger == 0)
    #expect(active?.rightTrigger == 255)
    #expect(active?.durationMilliseconds == 100)
    model.stopRumble()
  }

  @Test
  @MainActor
  func repeatedRumbleRunsCompleteWithOneCommandEach() async {
    let gateway = InputTestGatewayStub()
    let rumbleSleep: InputTestViewModel.Sleep = { _ in }
    let model = InputTestViewModel(gateway: gateway, rumbleSleep: rumbleSleep)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.leftMain] = 200

    for expectedCount in 1...3 {
      model.testRumble()
      await waitUntil { model.outputState == .succeeded(.rumble) }
      #expect(await gateway.rumbleCalls.count == expectedCount)
      #expect(!model.canStopRumble)
    }

    #expect(
      await gateway.rumbleCalls.allSatisfy { $0.left == 200 && $0.durationMilliseconds == 300 }
    )
  }

  @Test
  @MainActor
  func explicitRumbleStopCancelsTheWaitAndSendsOneZeroCommand() async {
    let gateway = InputTestGatewayStub()
    let rumbleSleep: InputTestViewModel.Sleep = { _ in try await Task.sleep(nanoseconds: .max) }
    let model = InputTestViewModel(gateway: gateway, rumbleSleep: rumbleSleep)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.leftMain] = 200

    model.testRumble()
    #expect(await gateway.waitForRumbleCalls(1))
    #expect(model.canStopRumble)
    model.stopRumble()
    #expect(await gateway.waitForRumbleCalls(2))

    let calls = await gateway.rumbleCalls
    #expect(calls.count == 2)
    #expect(calls[0].left == 200)
    #expect(calls[1].left == 0)
    #expect(calls[1].right == 0)
    #expect(calls[1].durationMilliseconds == 0)
    #expect(model.outputState == .idle)
    #expect(!model.canStopRumble)
  }

}
