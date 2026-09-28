import Testing

@testable import OpenJoystickDriverKit

struct ControllerProfileCapabilitiesTests {
  @Test
  func exactCatalogLookupDistinguishesKnownAndUnknownControllers() {
    let registry = ProtocolDriverRegistry()
    let dualShock4 = registry.profileCapabilities(
      for: DeviceIdentifier(vendorID: 0x054C, productID: 0x05C4)
    )

    #expect(dualShock4?.physicalInput.motion == true)
    #expect(dualShock4?.physicalInput.touchContactCount == 2)
    #expect(
      registry.profileCapabilities(for: DeviceIdentifier(vendorID: 0xFFFF, productID: 0xFFFF))
        == nil
    )
  }

  @Test
  func intersectionKeepsOnlyCapabilitiesSharedByEveryController() {
    let first = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(
        controls: ControlID.xboxLayout.union([.touchpadClick, .microphone]),
        touchContactCount: 2,
        motion: true
      ),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.leftMain, .rightMain],
        lightingFeatures: [.programmableColor, .programmableBrightness],
        adaptiveTriggers: [.left, .right]
      ),
      buttonLabels: .standard
    )
    let second = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(
        controls: [.faceSouth, .leftTrigger, .touchpadClick],
        touchContactCount: 1
      ),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.rightMain],
        lightingFeatures: [.programmableColor],
        adaptiveTriggers: [.right]
      ),
      buttonLabels: .standard
    )

    let result = first.intersecting(second)
    #expect(!result.physicalInput.motion)
    #expect(result.physicalInput.touchContactCount == 1)
    #expect(result.physicalInput.controls == [.faceSouth, .leftTrigger, .touchpadClick])
    #expect(result.physicalInput.touchSurfaces == [.primary])
    #expect(result.physicalOutput.rumbleMotors == [.rightMain])
    #expect(result.physicalOutput.lightingFeatures == [.programmableColor])
    #expect(result.physicalOutput.adaptiveTriggers == [.right])
    #expect(!result.supportsStickAxes)
    #expect(result.supportsAnalogTriggers)
  }
}
