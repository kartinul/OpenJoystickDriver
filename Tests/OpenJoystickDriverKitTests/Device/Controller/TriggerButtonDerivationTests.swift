import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct TriggerButtonDerivationTests {
  private static let analogOnly = ControllerCapabilities(controls: ControlID.xboxLayout)
  private static let digital = ControllerCapabilities(
    controls: ControlID.xboxLayout.union([.leftTriggerButton, .rightTriggerButton])
  )

  private func derive(
    left: UInt16,
    right: UInt16 = 0,
    after previous: ControllerState = .neutral,
    capabilities: ControllerCapabilities = Self.analogOnly
  ) -> Set<ControlID> {
    var state = ControllerState.neutral
    state.leftTrigger = UnipolarValue(left)
    state.rightTrigger = UnipolarValue(right)
    return TriggerButtonDerivation.applying(
      to: state,
      previous: previous,
      capabilities: capabilities
    ).pressed
  }

  @Test
  func policyReusesTheRemappingDigitalActivationDefaults() {
    #expect(
      TriggerButtonDerivation.pressThreshold
        == UnipolarValue(normalized: Float(RemappingAxisTuning.defaultDigitalActivationThreshold))
    )
    #expect(
      TriggerButtonDerivation.releaseThreshold
        == UnipolarValue(
          normalized: Float(
            RemappingAxisTuning.defaultDigitalActivationThreshold
              - RemappingTransform.hysteresisWidth
          )
        )
    )
    #expect(TriggerButtonDerivation.pressThreshold.rawValue == 32_767)
    #expect(TriggerButtonDerivation.releaseThreshold.rawValue == 29_490)
  }

  @Test
  func pressesAtTheThresholdAndReleasesOnlyBelowTheHysteresisBand() {
    #expect(derive(left: 32_766).isEmpty)
    #expect(derive(left: 32_767) == [.leftTriggerButton])
    #expect(derive(left: 0, right: 65_535) == [.rightTriggerButton])

    let held = snapshot(.press(.leftTriggerButton))
    #expect(derive(left: 29_491, after: held) == [.leftTriggerButton])
    #expect(derive(left: 29_490, after: held).isEmpty)
    #expect(derive(left: 29_491).isEmpty)
  }

  @Test
  func aDeclaredDigitalTriggerIsNeverDerived() {
    #expect(derive(left: 65_535, capabilities: Self.digital).isEmpty)
    var state = snapshot(.press(.rightTriggerButton))
    state.rightTrigger = .min
    let kept = TriggerButtonDerivation.applying(
      to: state,
      previous: .neutral,
      capabilities: Self.digital
    )
    #expect(kept == state)
  }

  @Test
  func aDigitalOnlyTriggerDerivesNothing() {
    let digitalOnly = ControllerCapabilities(
      controls: ControlID.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTriggerButton, .rightTriggerButton,
      ])
    )
    #expect(derive(left: 65_535, capabilities: digitalOnly).isEmpty)
    #expect(digitalOnly.normalized == digitalOnly)
  }

  @Test
  func normalizedCapabilitiesListEachDerivedTriggerButton() {
    #expect(
      Self.analogOnly.normalized.controls
        == Self.analogOnly.controls.union([.leftTriggerButton, .rightTriggerButton])
    )
    #expect(Self.digital.normalized == Self.digital)
    #expect(XUSBDriver().capabilities.normalized.controls.contains(.leftTriggerButton))
    #expect(DualShock4Driver().capabilities.normalized == DualShock4Driver().capabilities)
  }

  /// The pipeline derives the button with hysteresis against its last normalized state, and a
  /// resumed session starts that memory from neutral.
  @Test
  func pipelineDerivesTriggerButtonsAndResumeForgetsTheHysteresis() async {
    let driver = OutputCharacterizationTests.ScriptedBatches([
      [.leftTrigger(0.6)], [.leftTrigger(0.47)], [.leftTrigger(0.4)], [.leftTrigger(0.47)],
    ])
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x045E, productID: 0x028E),
      transport: .hid(locationID: 1),
      driver: driver,
      dispatcher: OutputCharacterizationTests.PipelineOutput(),
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await pipeline.start()
    var pressed: [Bool] = []
    for batch in 0..<3 {
      _ = await pipeline.feedHIDData(Data([UInt8(batch)]))
      pressed.append(await pipeline.inputState().pressed.contains(.leftTriggerButton))
    }
    #expect(pressed == [true, true, false])
    _ = await pipeline.feedHIDData(Data([0]))
    #expect(await pipeline.inputState().pressed.contains(.leftTriggerButton))
    #expect(await pipeline.suspendControllerSession())
    #expect(await pipeline.resumeControllerSession())
    _ = await pipeline.feedHIDData(Data([3]))
    #expect(!(await pipeline.inputState().pressed.contains(.leftTriggerButton)))
    await pipeline.stop()
  }
}
