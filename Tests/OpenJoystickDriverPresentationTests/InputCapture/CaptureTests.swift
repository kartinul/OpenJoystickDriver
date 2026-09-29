import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.serialized)
struct InputCaptureTests {
  @Test
  func listensUntilItFindsAControllerControl() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    let released = ControllerState.neutral
    var pressed = released
    pressed.pressed = [.faceSouth]
    let gateway = GatewayStub(inputSequence: [released, pressed])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(let capturedSelector, let capturedState, let detectedSource) = captureState
    else {
      Issue.record("Expected the next meaningful controller transition")
      return
    }
    #expect(capturedSelector == selector)
    #expect(detectedSource == .button(.south))
    #expect(
      RuntimePresentation.detectedSource(from: capturedState, labels: .standard) == .button(.south)
    )
  }

  @Test
  func listenIgnoresAControlHeldBeforeListening() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    var held = ControllerState.neutral
    held.pressed = [.faceSouth]
    let released = ControllerState.neutral
    var pressedAgain = released
    pressedAgain.pressed = [.faceSouth]
    let gateway = GatewayStub(inputSequence: [held, held, released, pressedAgain])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(_, let state, let detectedSource) = captureState else {
      Issue.record("Expected a later press after the held baseline")
      return
    }
    #expect(detectedSource == .button(.south))
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.south))
  }

  @Test
  func listenPublishesTheTransitionSourceWhenAnotherControlWasAlreadyHeld() async {
    let selector = RuntimeDeviceSelector(
      vendorID: 0x1234,
      productID: 0x5678,
      runtimeIdentifier: "live"
    )
    var baseline = ControllerState.neutral
    baseline.pressed = [.faceSouth]
    var changed = baseline
    changed.pressed = [.faceSouth, .faceEast]
    let gateway = GatewayStub(inputSequence: [baseline, changed])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.listenForInput(for: selector)

    let captureState = await MainActor.run { viewModel.inputCaptureState }
    guard case .detected(_, _, let detectedSource) = captureState else {
      Issue.record("Expected the newly pressed control")
      return
    }
    #expect(detectedSource == .button(.east))
  }

  @Test
  func detectedSourceUsesCanonicalButtonDpadAndAxisOrder() {
    var state = ControllerState.neutral
    state.pressed = [.faceEast, .faceSouth]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.south))

    state.pressed = []
    state.hat = .west
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .dpad(.left))

    state.hat = .neutral
    state.leftStick.x = BipolarValue(normalized: -0.75)
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard)
        == .axisDirection(.leftStickX, .negative)
    )

    state.leftStick.x = BipolarValue(normalized: 0.2)
    state.rightTrigger = UnipolarValue(normalized: 0.7)
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard)
        == .axisDirection(.rightTrigger, .positive)
    )

    state.rightTrigger = UnipolarValue(normalized: 0.2)
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == nil)
  }

  @Test
  func detectedTransitionCapturesNewTouchSurfaceButNotHeldContactMovement() {
    let previous = ControllerState.neutral
    var touched = previous
    touched.touch = [touchSample(surface: .right, x: 10)]
    var moved = touched
    moved.touch = [touchSample(surface: .right, x: 50)]

    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: touched, labels: .standard)
        == .touchContact(.right)
    )
    #expect(
      RuntimePresentation.detectedTransition(from: touched, to: moved, labels: .standard) == nil
    )
  }

  @Test
  func detectedSourceIncludesNamedExtraAndDigitalControllerAliases() {
    var state = ControllerState.neutral
    state.pressed = [.auxiliary1]
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.leftFunction)
    )

    state.pressed = [.auxiliary2]
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.rightFunction)
    )

    state.pressed = [.paddleLeft1]
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.leftPaddle)
    )

    state.pressed = [.paddleRight1]
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.rightPaddle)
    )

    state.pressed = [.auxiliary3]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.leftSL))

    state.pressed = [.auxiliary4]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.leftSR))

    state.pressed = [.auxiliary5]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.rightSL))

    state.pressed = [.auxiliary6]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.rightSR))

    state.pressed = [.share]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(.share))

    state.pressed = [.leftTriggerButton]
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard)
        == .button(.leftTriggerClick)
    )

    state.pressed = [.rightTriggerButton]
    #expect(
      RuntimePresentation.detectedSource(from: state, labels: .standard)
        == .button(.rightTriggerClick)
    )
  }

  @Test
  func detectedSourceIgnoresReservedGuideAndHomeControls() {
    var state = ControllerState.neutral
    state.pressed = [.guide]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == nil)

    state.pressed = [.guide]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == nil)
  }

  @Test
  func detectedTransitionUsesCanonicalAliasesAndAxisThresholds() {
    let previous = ControllerState.neutral
    var current = previous
    current.pressed = [.microphone]
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current, labels: .standard)
        == .button(.mute)
    )

    current.pressed = []
    current.leftStick.x = BipolarValue(normalized: 0.75)
    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current, labels: .standard)
        == .axisDirection(.leftStickX, .positive)
    )

    var held = current
    held.leftStick.x = BipolarValue(normalized: 0.8)
    #expect(
      RuntimePresentation.detectedTransition(from: current, to: held, labels: .standard) == nil
    )

    held.leftStick.x = BipolarValue(normalized: -0.8)
    #expect(
      RuntimePresentation.detectedTransition(from: current, to: held, labels: .standard)
        == .axisDirection(.leftStickX, .negative)
    )
  }

  @Test
  func detectedTransitionIgnoresReleaseOnlyChanges() {
    var previous = ControllerState.neutral
    previous.pressed = [.faceSouth, .faceEast]
    var current = previous
    current.pressed = [.faceEast]

    #expect(
      RuntimePresentation.detectedTransition(from: previous, to: current, labels: .standard) == nil
    )
  }

  private func touchSample(surface: ControllerTouchSurface, x: UInt16) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: surface,
      timestamp: MonotonicTimestamp(nanoseconds: 0),
      contacts: [ControllerTouchContact(slot: 0, isActive: true, x: x, y: 10)]
    )
  }
}
