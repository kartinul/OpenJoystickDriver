import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileSelectorTests {
  private typealias Selector = VirtualHIDProfileSelector

  @Test
  func aFullXboxLayoutSelectsTheXboxProfile() throws {
    let selection = try Selector.select(controls: ControlID.xboxLayout, override: nil)
    #expect(selection == .init(profileID: .xboxOneSBluetooth, source: .automatic))
  }

  @Test
  func everyDeclaredControlTogetherStillSelectsTheXboxProfile() throws {
    let selection = try Selector.select(controls: Set(ControlID.allCases), override: nil)
    #expect(selection == .init(profileID: .xboxOneSBluetooth, source: .automatic))
  }

  @Test
  func extendedAndSystemControlsDoNotForceTheGenericProfile() throws {
    let controls = ControlID.xboxLayout.union([
      .guide, .share, .capture, .touchpadClick, .microphone, .paddleLeft1, .paddleRight2,
      .auxiliary8, .leftTrackpadClick, .rightTrackpadTouch,
    ])
    #expect(try Selector.select(controls: controls, override: nil).profileID == .xboxOneSBluetooth)
  }

  @Test
  func digitalOnlyTriggersFitTheXboxTriggerSlots() throws {
    let controls = ControlID.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
      .leftTriggerButton, .rightTriggerButton,
    ])
    #expect(try Selector.select(controls: controls, override: nil).profileID == .xboxOneSBluetooth)
  }

  @Test
  func aSubsetOfTheXboxLayoutSelectsTheXboxProfile() throws {
    let controls: Set<ControlID> = [.dpad, .faceSouth, .faceEast, .view, .menu]
    #expect(try Selector.select(controls: controls, override: nil).profileID == .xboxOneSBluetooth)
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func theAdvancedOverrideWins(profile: VirtualHIDProfileID) throws {
    let selection = try Selector.select(controls: ControlID.xboxLayout, override: profile)
    #expect(selection == .init(profileID: profile, source: .override))
  }

  /// A new `ControlID` must be classified here on purpose: primary controls decide the profile.
  @Test
  func everyControlOutsideTheXboxLayoutAndTriggerButtonsIsNonPrimary() {
    let nonPrimary: Set<ControlID> = [
      .guide, .share, .capture, .touchpadClick, .microphone, .paddleLeft1, .paddleLeft2,
      .paddleRight1, .paddleRight2, .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5,
      .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick,
      .rightTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch,
    ]
    #expect(Set(ControlID.allCases).subtracting(Selector.primaryControls) == nonPrimary)
  }

  /// Both profiles carry every primary control today, so automatic selection never reaches
  /// `hid-generic`, an override is always satisfiable, and `virtual-profile-unavailable` cannot
  /// occur with the real profiles. The synthetic-slot tests below cover those branches.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func everyProfileRepresentsEveryPrimaryControl(profile: VirtualHIDProfileID) {
    #expect(Selector.represents(Selector.primaryControls, in: profile.representableControls))
  }

  @Test
  func representationChecksEachControlAgainstTheProfileSlots() {
    #expect(Selector.represents([.leftTriggerButton], in: [.leftTrigger]))
    #expect(!Selector.represents([.leftTriggerButton], in: [.rightTrigger]))
    #expect(!Selector.represents([.faceSouth], in: [.faceEast]))
  }

  @Test
  func controlsTheXboxSlotsLackSelectTheGenericProfile() throws {
    let slots: [VirtualHIDProfileID: Set<ControlID>] = [
      .xboxOneSBluetooth: [.faceSouth], .generic: [.faceSouth, .faceEast],
    ]
    let selection = try Selector.select(controls: [.faceSouth, .faceEast], override: nil) {
      slots[$0, default: []]
    }
    #expect(selection == .init(profileID: .generic, source: .automatic))
  }

  @Test
  func anUnsatisfiableOverrideFallsBackToAutomaticSelection() throws {
    let slots: [VirtualHIDProfileID: Set<ControlID>] = [
      .xboxOneSBluetooth: [.faceSouth, .faceEast], .generic: [.faceSouth],
    ]
    let selection = try Selector.select(controls: [.faceSouth, .faceEast], override: .generic) {
      slots[$0, default: []]
    }
    #expect(
      selection == .init(profileID: .xboxOneSBluetooth, source: .automaticAfterRejecting(.generic))
    )
  }

  @Test
  func controlsNoProfileCarriesFailWithVirtualProfileUnavailable() {
    #expect(throws: ProtocolBindingReason.virtualProfileUnavailable) {
      try Selector.select(controls: [.faceSouth], override: nil) { _ in [] }
    }
  }
}
