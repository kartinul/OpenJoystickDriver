import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct RuntimeExtraButtonTests {
  @Test(arguments: [
    RemappingButton.leftFunction, .rightFunction, .leftPaddle, .rightPaddle, .leftSL, .leftSR,
    .rightSL, .rightSR, .leftGrip, .rightGrip, .leftPadClick, .rightPadClick,
  ])
  func captureAndAuthoringExposeInputOnlyButtons(button: RemappingButton) throws {
    var state = ControllerState.neutral
    state.pressed = [try #require(button.controlID(labels: .standard))]
    #expect(RuntimePresentation.detectedSource(from: state, labels: .standard) == .button(button))
    #expect(SourceOption.options().contains { $0.source == .button(button) })
    let destinations = DestinationOption.options(
      for: .button(button),
      including: .gamepadButton(button)
    )
    #expect(!destinations.contains { $0.destination == .gamepadButton(button) })
    #expect(destinations.contains { $0.destination == .keyboard(key: .space, modifiers: []) })
  }
}
