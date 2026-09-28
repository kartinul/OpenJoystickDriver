import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingExtraButtonTests {
  @Test(arguments: [
    (ControlID.paddleLeft2, RemappingButton.leftGrip), (ControlID.paddleRight2, .rightGrip),
    (ControlID.leftTrackpadClick, .leftPadClick), (ControlID.rightTrackpadClick, .rightPadClick),
    (ControlID.auxiliary3, .leftSL), (ControlID.auxiliary4, .leftSR),
    (ControlID.auxiliary5, .rightSL), (ControlID.auxiliary6, .rightSR),
    (ControlID.auxiliary1, .leftFunction), (ControlID.auxiliary2, .rightFunction),
    (ControlID.paddleLeft1, .leftPaddle), (ControlID.paddleRight1, .rightPaddle),
  ])
  func extraButtonCanHoldAndReleaseAKeyboardAction(
    physical: ControlID,
    source: RemappingButton
  ) throws {
    let profile = profile(source: source)
    try profile.validate()
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self,
      from: JSONEncoder().encode(profile)
    )
    var engine = RemappingEngineState()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    #expect(
      engine.process(inputs: [.press(physical)], from: identifier, profile: decoded, at: 0) == [
        .system(.keyDown(.space))
      ]
    )
    #expect(
      engine.process(inputs: [.release(physical)], from: identifier, profile: decoded, at: 1) == [
        .system(.keyUp(.space))
      ]
    )
    #expect(engine.drain().isEmpty)
  }

  @Test(arguments: [
    RemappingButton.leftGrip, .rightGrip, .leftPadClick, .rightPadClick, .leftSL, .leftSR, .rightSL,
    .rightSR, .leftFunction, .rightFunction, .leftPaddle, .rightPaddle,
  ])
  func inputOnlyButtonsCannotBeVirtualDestinations(_ button: RemappingButton) {
    let invalid = RemappingProfile(
      name: "Invalid output",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(button))]
    )
    #expect(throws: RemappingValidationError.unsupportedGamepadButton(button)) {
      try invalid.validate()
    }
    #expect(RemappingGamepadState(buttons: [button]) == .neutral)
  }

  @Test
  func rightPadPassthroughIsConsumedByAnExplicitMapping() throws {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    for mapped in [false, true] {
      let bindings = mapped ? profile(source: .rightPadClick).bindings : []
      let profile = RemappingProfile(
        name: "Pad passthrough",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
        bindings: bindings
      )
      try profile.validate()
      var engine = RemappingEngineState()
      let press = engine.process(
        inputs: [.press(.rightTrackpadClick)],
        from: identifier,
        profile: profile,
        at: 0
      )
      let release = engine.process(
        inputs: [.release(.rightTrackpadClick)],
        from: identifier,
        profile: profile,
        at: 1
      )
      if mapped {
        #expect(press == [.system(.keyDown(.space))])
        #expect(release == [.system(.keyUp(.space))])
      } else {
        #expect(press == [.gamepad(RemappingGamepadState(buttons: [.rightStick]), identifier)])
        #expect(release == [.gamepad(.neutral, identifier)])
      }
    }
  }

  private func profile(source: RemappingButton) -> RemappingProfile {
    RemappingProfile(
      name: "Extra button",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(source),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
  }
}
