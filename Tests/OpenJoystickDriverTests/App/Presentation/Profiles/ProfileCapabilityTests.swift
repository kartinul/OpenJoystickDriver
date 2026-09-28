import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfileCapabilityTests {
  @Test(arguments: [
    // (VID, PID, supported buttons, unsupported buttons)
    (0x054C, 0x09CC, [RemappingButton.options, .share], [RemappingButton.start, .back]),
    (0x045E, 0x028E, [.start, .back], [.options, .share]),
    (0x057E, 0x2009, [.start, .back, .share], [.options]),
  ])
  func menuViewAndShareSourcesFollowTheFamilyLabels(
    vendorID: Int,
    productID: Int,
    supported: [RemappingButton],
    unsupported: [RemappingButton]
  ) throws {
    let capabilities = try #require(
      ProfileCapabilityResolver.resolve(
        profile: makeProfile(vendorID: UInt16(vendorID), productID: UInt16(productID)),
        connectedDevices: [],
        registry: ProtocolDriverRegistry()
      )
    )
    for button in supported {
      #expect(ProfileCapabilityPolicy.supports(.button(button), capabilities: capabilities))
    }
    for button in unsupported {
      #expect(!ProfileCapabilityPolicy.supports(.button(button), capabilities: capabilities))
    }
  }

  @Test
  func unknownDeviceKeepsEveryStandardSourceSelectable() {
    for source: RemappingSource in [.dpad(.up), .button(.south), .button(.start), .button(.back)] {
      #expect(ProfileCapabilityPolicy.supports(source, capabilities: .unknown))
    }
  }

  @Test
  func joyConPairProfileOffersBothHalvesControls() throws {
    func profile(pair: RemappingJoyConPairSettings?) -> RemappingProfile {
      RemappingProfile(
        name: "Joy-Con",
        device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
        applicationScope: .global,
        joyConPair: pair,
        bindings: []
      )
    }
    let registry = ProtocolDriverRegistry()
    let single = try #require(
      ProfileCapabilityResolver.resolve(
        profile: profile(pair: nil),
        connectedDevices: [],
        registry: registry
      )
    )
    let pair = try #require(
      ProfileCapabilityResolver.resolve(
        profile: profile(pair: RemappingJoyConPairSettings(gyroSelection: .left)),
        connectedDevices: [],
        registry: registry
      )
    )

    #expect(!single.physicalInput.controls.contains(.faceSouth))
    #expect(!single.physicalInput.controls.contains(.rightStickX))
    #expect(
      pair.physicalInput.controls.isSuperset(of: [.dpad, .faceSouth, .leftStickX, .rightStickX])
    )
    #expect(pair.physicalInput.controls.isSuperset(of: single.physicalInput.controls))
  }

  @Test
  func resolverIntersectsMatchingLiveDevicesBeforeUsingCatalog() {
    let profile = makeProfile(vendorID: 0x054C, productID: 0x05C4)
    let full = device(
      input: ControllerCapabilities(
        controls: ControlID.xboxLayout.union([.guide, .touchpadClick]),
        touchContactCount: 2,
        motion: true
      ),
      output: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.leftMain, .rightMain],
        lightingFeatures: [.programmableColor]
      )
    )
    let limited = device(
      input: ControllerCapabilities(controls: [.dpad, .faceSouth, .leftStickClick]),
      output: PhysicalControllerOutputCapabilities(rumbleMotors: [.leftMain])
    )

    let result = ProfileCapabilityResolver.resolve(
      profile: profile,
      connectedDevices: [full, limited],
      registry: ProtocolDriverRegistry()
    )

    #expect(result?.physicalOutput.rumbleMotors == [.leftMain])
    #expect(
      result?.physicalInput
        == ControllerCapabilities(controls: [.dpad, .faceSouth, .leftStickClick])
    )
    #expect(result?.supportsStickAxes == false)
    #expect(result?.supportsAnalogTriggers == false)
  }

  @Test
  func resolverUsesExactCatalogOfflineAndRejectsUnknownIdentity() {
    #expect(
      ProfileCapabilityResolver.resolve(
        profile: makeProfile(vendorID: 0x054C, productID: 0x05C4),
        connectedDevices: [],
        registry: ProtocolDriverRegistry()
      )?.physicalInput.motion == true
    )
    #expect(
      ProfileCapabilityResolver.resolve(
        profile: makeProfile(vendorID: 0xFFFF, productID: 0xFFFF),
        connectedDevices: [],
        registry: ProtocolDriverRegistry()
      ) == nil
    )
  }

  @Test
  func sourceAndDestinationOptionsRetainUnsupportedCurrentValuesOnly() {
    let capabilities = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(controls: [.faceSouth, .paddleLeft1]),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: [.leftMain],
        lightingFeatures: [.programmableColor]
      ),
      buttonLabels: .standard
    )

    #expect(ProfileCapabilityPolicy.supports(.button(.south), capabilities: capabilities))
    #expect(!ProfileCapabilityPolicy.supports(.button(.start), capabilities: capabilities))
    #expect(!ProfileCapabilityPolicy.supports(.dpad(.up), capabilities: capabilities))
    #expect(ProfileCapabilityPolicy.supports(.button(.leftPaddle), capabilities: capabilities))
    #expect(!ProfileCapabilityPolicy.supports(.button(.rightPaddle), capabilities: capabilities))
    #expect(!ProfileCapabilityPolicy.supports(.axis(.leftStickX), capabilities: capabilities))
    #expect(!ProfileCapabilityPolicy.supports(.motionLean(.left), capabilities: capabilities))
    #expect(!ProfileCapabilityPolicy.supports(.touchContact(.primary), capabilities: capabilities))

    let retainedSources = SourceOption.options(
      including: .motionLean(.left),
      capabilities: capabilities
    )
    #expect(retainedSources.last?.source == .motionLean(.left))
    #expect(retainedSources.last?.isSupported == false)

    let retainedDestination = RemappingDestination.physical(.brightness(0.5))
    let destinations = DestinationOption.options(
      for: .button(.south),
      including: retainedDestination,
      capabilities: capabilities
    )
    #expect(
      destinations.contains { $0.destination == .physical(.rumble(motor: .leftMain, intensity: 1)) }
    )
    #expect(
      !destinations.contains {
        $0.destination == .physical(.rumble(motor: .rightMain, intensity: 1))
      }
    )
    #expect(destinations.last?.destination == retainedDestination)
    #expect(destinations.last?.isSupported == false)
  }

  @Test
  func sourcePolicyMapsRemappingControlsToDeclaredControlIDs() {
    let capabilities = ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(
        controls: [
          .menu, .view, .share, .paddleLeft2, .auxiliary3, .leftTrackpadClick, .rightTrigger,
          .leftTrackpadTouch,
        ],
        touchContactCount: 1,
        motion: true
      ),
      physicalOutput: .none,
      buttonLabels: .standard
    )
    let supported: [RemappingSource] = [
      .button(.start), .button(.back), .button(.share), .button(.leftGrip), .button(.leftSL),
      .button(.leftPadClick), .axis(.rightTrigger), .triggerStage(.right, .soft),
      .motionLean(.left), .touchContact(.left),
    ]
    let unsupported: [RemappingSource] = [
      .button(.guide), .button(.options), .button(.rightGrip), .button(.leftSR),
      .button(.rightPadClick), .axis(.leftTrigger), .triggerStage(.left, .soft),
      .touchContact(.right), .touchContact(.primary),
    ]
    for source in supported {
      #expect(ProfileCapabilityPolicy.supports(source, capabilities: capabilities))
    }
    for source in unsupported {
      #expect(!ProfileCapabilityPolicy.supports(source, capabilities: capabilities))
    }
  }

  private func makeProfile(vendorID: UInt16, productID: UInt16) -> RemappingProfile {
    RemappingProfile(
      name: "Capability test",
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: .global,
      bindings: []
    )
  }

  private func device(
    input: ControllerCapabilities,
    output: PhysicalControllerOutputCapabilities
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x054C,
      productID: 0x05C4,
      protocolBinding: ProtocolBindingID(.sonyDualShock4, variant: .usb),
      connection: "HID",
      serialNumber: nil,
      physicalOutputCapabilities: output,
      capabilities: input
    )
  }
}
