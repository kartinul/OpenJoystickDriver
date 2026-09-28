import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension UserSpaceOutputDispatcherLifecycleTests {
  @Test
  func everyAcceptedButtonPreservesHoldReleaseAndLaterInput() async {
    let supported: [(ControlID, ControllerButtonLabels, ExpectedButtonOutput)] = [
      (.faceSouth, .standard, .bit(0)), (.faceSouth, .playStation, .bit(0)),
      (.faceEast, .standard, .bit(1)), (.faceWest, .standard, .bit(2)),
      (.faceNorth, .standard, .bit(3)), (.leftShoulder, .standard, .bit(4)),
      (.rightShoulder, .standard, .bit(5)), (.leftStickClick, .standard, .bit(6)),
      (.rightStickClick, .standard, .bit(7)), (.rightTrackpadClick, .standard, .bit(7)),
      (.menu, .standard, .bit(8)), (.menu, .playStation, .bit(8)), (.view, .standard, .bit(9)),
      (.view, .playStation, .bit(15)), (.guide, .standard, .bit(10)), (.share, .standard, .bit(15)),
      (.capture, .nintendo, .bit(15)), (.leftTriggerButton, .standard, .leftTrigger),
      (.rightTriggerButton, .standard, .rightTrigger),
    ]
    let unsupported: [ControlID] = [
      .paddleLeft1, .paddleLeft2, .paddleRight1, .paddleRight2, .auxiliary1, .auxiliary2,
      .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch,
      .rightStickTouch, .leftTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch, .touchpadClick,
      .microphone,
    ]
    let analog: [ControlID] = [
      .dpad, .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
    ]
    #expect(Set(supported.map(\.0) + unsupported + analog) == Set(ControlID.allCases))

    for (control, labels, output) in supported {
      let backend = UserSpaceDispatcherTestBackend()
      let format = ContinuitySnapshotReportFormat()
      let dispatcher = UserSpaceOutputDispatcher(
        testBackendFactory: { _ in backend },
        format: format
      )
      let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
      var expected = VirtualGamepadState()

      await dispatcher.dispatch(changes: [.press(control)], from: identifier, labels: labels)
      set(output, pressed: true, in: &expected)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))

      await dispatcher.dispatch(
        changes: [.leftStick(x: 0.5, y: -0.25)],
        from: identifier,
        labels: labels
      )
      expected.leftStickX = Int16(0.5 * 32_767)
      expected.leftStickY = Int16(-0.25 * 32_767)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))

      await dispatcher.dispatch(changes: [.release(control)], from: identifier, labels: labels)
      set(output, pressed: false, in: &expected)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))

      await dispatcher.dispatch(changes: [.rightTrigger(0.75)], from: identifier, labels: labels)
      expected.rightTrigger = Int16(0.75 * 32_767)
      #expect(backend.publishedReports().last == format.buildInputReport(from: expected))
      await dispatcher.close()
    }

    let backend = UserSpaceDispatcherTestBackend()
    let format = ContinuitySnapshotReportFormat()
    let dispatcher = UserSpaceOutputDispatcher(testBackendFactory: { _ in backend }, format: format)
    let identifier = DeviceIdentifier(vendorID: 3, productID: 4)
    let neutral = format.buildInputReport(from: VirtualGamepadState())
    for control in unsupported {
      await dispatcher.dispatch(changes: [.press(control)], from: identifier)
      #expect(backend.publishedReports().last == neutral, "\(control) must remain unsupported")
      await dispatcher.dispatch(changes: [.release(control)], from: identifier)
    }
    await dispatcher.close()
  }

  @Test
  func dpadSticksAndTriggersPreserveTransitionsAcrossUnrelatedInput() async {
    let dpadCases: [(HatDirection, GamepadHIDDescriptor.Hat)] = [
      (.north, .north), (.northEast, .northEast), (.east, .east), (.southEast, .southEast),
      (.south, .south), (.southWest, .southWest), (.west, .west), (.northWest, .northWest),
    ]
    for (direction, hat) in dpadCases {
      var expected = VirtualGamepadState()
      await verifyContinuity(
        pressed: .hat(direction),
        heldWith: .leftStick(x: 0.5, y: -0.25),
        released: .hat(.neutral),
        later: .rightTrigger(0.75)
      ) { stage in
        switch stage {
        case 0:
          expected.hat = hat
          expected.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
        case 1:
          expected.leftStickX = Int16(0.5 * 32_767)
          expected.leftStickY = Int16(-0.25 * 32_767)
        case 2:
          expected.hat = .neutral
          expected.buttons = 0
        default: expected.rightTrigger = Int16(0.75 * 32_767)
        }
        return expected
      }
    }

    let analogCases: [(InputChange, InputChange, (inout VirtualGamepadState, Bool) -> Void)] = [
      (
        .leftStick(x: 0.75, y: -0.5), .leftStick(x: 0, y: 0),
        { state, pressed in
          state.leftStickX = pressed ? Int16(0.75 * 32_767) : 0
          state.leftStickY = pressed ? Int16(-0.5 * 32_767) : 0
        }
      ),
      (
        .rightStick(x: -0.5, y: 0.75), .rightStick(x: 0, y: 0),
        { state, pressed in
          state.rightStickX = pressed ? Int16(-0.5 * 32_767) : 0
          state.rightStickY = pressed ? Int16(0.75 * 32_767) : 0
        }
      ),
      (
        .leftTrigger(0.75), .leftTrigger(0),
        { state, pressed in state.leftTrigger = pressed ? Int16(0.75 * 32_767) : 0 }
      ),
      (
        .rightTrigger(0.75), .rightTrigger(0),
        { state, pressed in state.rightTrigger = pressed ? Int16(0.75 * 32_767) : 0 }
      ),
    ]
    for (pressed, released, update) in analogCases {
      var expected = VirtualGamepadState()
      await verifyContinuity(
        pressed: pressed,
        heldWith: .press(.faceWest),
        released: released,
        later: .press(.faceSouth)
      ) { stage in
        switch stage {
        case 0: update(&expected, true)
        case 1: expected.buttons |= 1 << 2
        case 2: update(&expected, false)
        default: expected.buttons |= 1
        }
        return expected
      }
    }
  }

  @Test
  func compatibilitySuppressionPublishesDeviceWithoutForwardingInput() async {
    let backend = UserSpaceDispatcherTestBackend()
    let creations = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      _ = creations.next()
      return backend
    }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    await dispatcher.setOutputSuppressed(true)

    await dispatcher.dispatch(changes: [.press(.faceSouth)], from: identifier)

    #expect(creations.current() == 1)
    #expect(backend.publishedReports().isEmpty)
    #expect(backend.counts().close == 0)
    await dispatcher.close()
  }

  @Test
  func compatibilitySuppressionNeutralizesWithoutRetiringDevice() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    await dispatcher.dispatch(changes: [.press(.faceSouth)], from: identifier)

    await dispatcher.setOutputSuppressed(true)

    #expect(
      backend.publishedReports().last
        == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    )
    #expect(backend.counts().close == 0)
    // Released while suppressed: a snapshot carries every held control, so South must be let go.
    await dispatcher.dispatch(changes: [.release(.faceSouth)], from: identifier)

    await dispatcher.setOutputSuppressed(false)
    await dispatcher.dispatch(changes: [.press(.faceEast)], from: identifier)
    var expected = VirtualGamepadState()
    expected.buttons = 1 << GamepadHIDDescriptor.ButtonBit.b.rawValue
    #expect(
      backend.publishedReports().last == OJDGenericGamepadFormat().buildInputReport(from: expected)
    )
    #expect(backend.counts().close == 0)
    await dispatcher.close()
  }

  @Test
  func neutralRetryAfterRetirementDoesNotCreateAnotherDevice() async throws {
    let creations = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      _ = creations.next()
      return UserSpaceDispatcherTestBackend()
    }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(creations.current() == 0)
    try await dispatcher.send(RemappingGamepadState(buttons: [.south]), for: identifier)
    await dispatcher.controllerDidStop(identifier)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(creations.current() == 1)
    await dispatcher.close()
  }

  @Test
  func stateHeldBeforeSuppressionIsRepublishedAfterItLifts() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    await dispatcher.dispatch(changes: [.press(.faceSouth)], from: identifier)
    let pressed = try #require(backend.publishedReports().last)

    await dispatcher.setOutputSuppressed(true)
    #expect(backend.publishedReports().last != pressed)
    await dispatcher.setOutputSuppressed(false)
    await dispatcher.dispatch(changes: [.press(.faceSouth)], from: identifier)

    #expect(backend.publishedReports().last == pressed)
    await dispatcher.close()
  }

  @Test
  func remappedReportsUseTheirOwnSuppressionGate() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    await dispatcher.setOutputSuppressed(true)
    await dispatcher.dispatch(changes: [.press(.faceSouth)], from: identifier)
    #expect(backend.publishedReports().isEmpty)
    try await dispatcher.send(RemappingGamepadState(buttons: [.north]), for: identifier)
    #expect(!backend.publishedReports().isEmpty)
    await dispatcher.setRemappingOutputSuppressed(true)
    await #expect(throws: CancellationError.self) {
      try await dispatcher.send(RemappingGamepadState(buttons: [.south]), for: identifier)
    }
    try await dispatcher.send(.neutral, for: identifier)
    #expect(
      backend.publishedReports().last
        == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    )
    await dispatcher.close()
  }

  @Test
  func remappedStatePreservesSmallAxesAndDistinctShareThenReplacesHeldState() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    try await dispatcher.send(
      RemappingGamepadState(buttons: [.share], axes: [.leftStickX: 0.01]),
      for: identifier
    )
    var expected = VirtualGamepadState()
    expected.buttons = 1 << 15
    expected.leftStickX = Int16(Float(0.01) * 32_767)
    #expect(
      backend.publishedReports().last == OJDGenericGamepadFormat().buildInputReport(from: expected)
    )
    try await dispatcher.send(RemappingGamepadState(buttons: [.back]), for: identifier)
    expected = VirtualGamepadState()
    expected.buttons = 1 << 9
    #expect(
      backend.publishedReports().last == OJDGenericGamepadFormat().buildInputReport(from: expected)
    )
    await dispatcher.setOutputSuppressed(true)
    try await dispatcher.send(.neutral, for: identifier)
    #expect(
      backend.publishedReports().last
        == OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    )
    await dispatcher.close()
  }

  @Test
  func remappingReceivesNativeDeliveryFailure() async {
    let backend = UserSpaceDispatcherTestBackend(failsSend: true)
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    await #expect(throws: UserSpaceDispatcherTestBackend.SendFailure.self) {
      try await dispatcher.send(
        RemappingGamepadState(buttons: [.south]),
        for: DeviceIdentifier(vendorID: 1, productID: 2)
      )
    }
    #expect(backend.counts().close == 1)
    await dispatcher.close()
  }

  @Test
  func activationCreatesAndNeutralizesEveryController() async throws {
    let created = LockedBackends()
    let dispatcher = UserSpaceOutputDispatcher { _ in
      let backend = UserSpaceDispatcherTestBackend()
      created.append(backend)
      return backend
    }
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
      DeviceIdentifier(vendorID: 5, productID: 6),
    ]

    try await dispatcher.activate(for: identifiers)

    #expect(created.snapshot().count == identifiers.count)
    #expect(created.snapshot().allSatisfy { $0.counts().send >= 1 })
    await dispatcher.close()
  }

  @Test
  func idleDevicePublishesOnlyOnInput() async throws {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher { _ in backend }
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

    try await dispatcher.activate(for: [identifier])
    let idleSends = backend.counts().send
    #expect(idleSends == 1)
    try await Task.sleep(for: .milliseconds(50))
    #expect(backend.counts().send == idleSends)

    let idle = try #require(backend.publishedReports().last)
    await dispatcher.dispatch(changes: [.press(.faceSouth)], from: identifier)
    #expect(backend.counts().send > idleSends)
    let pressed = try #require(backend.publishedReports().last)
    #expect(pressed != idle)

    let pressedSends = backend.counts().send
    // The same snapshot again publishes nothing.
    await dispatcher.dispatch(changes: [], from: identifier)
    #expect(backend.counts().send == pressedSends)

    await dispatcher.close()
    #expect(backend.counts().close == 1)
  }

  @Test


  func activationSendFailureClosesPartialDevicesForEveryFailurePosition() async {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
      DeviceIdentifier(vendorID: 5, productID: 6),
    ]
    for failureIndex in identifiers.indices {
      let created = LockedBackends()
      let attempt = LockedCounter()
      let dispatcher = UserSpaceOutputDispatcher { _ in
        let index = attempt.next()

        let backend = UserSpaceDispatcherTestBackend(failsSend: index == failureIndex)
        created.append(backend)
        return backend
      }

      do {
        try await dispatcher.activate(for: identifiers)
        Issue.record("Activation unexpectedly succeeded")
      } catch {}

      #expect(created.snapshot().count == failureIndex + 1)
      #expect(created.snapshot().allSatisfy { $0.counts().close == 1 })
    }
  }

}
