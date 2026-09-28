import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

extension RemappingOutputRouterTests {
  @Test
  func calibrationRejectsUnknownControllersAndIneligibleRoutes() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    await #expect(throws: RemappingMotionCalibrationError.controllerUnavailable) {
      try await harness.router.motionCalibration(for: device.runtimeIdentifier, command: .start)
    }
    try await harness.router.dispatchCausally(.activation, from: device)
    let status = try await harness.router.motionCalibration(for: device.runtimeIdentifier)
    #expect(!status.hasMotionBaseline && !status.isCollecting)
    await #expect(throws: RemappingMotionCalibrationError.motionUnavailable) {
      try await harness.router.motionCalibration(for: device.runtimeIdentifier, command: .start)
    }
    harness.foreground.set("com.example.Other")
    await #expect(throws: RemappingMotionCalibrationError.motionUnavailable) {
      try await harness.router.motionCalibration(for: device.runtimeIdentifier, command: .reset)
    }
    #expect(await harness.router.status(for: device)?.eligibility == .targetApplicationNotFrontmost)
    try await harness.router.stopController(device)
    await #expect(throws: RemappingMotionCalibrationError.controllerUnavailable) {
      try await harness.router.motionCalibration(for: device.runtimeIdentifier)
    }
    try await harness.router.shutdown()
  }

  @Test(arguments: [false, true])


  func releaseFailureStillRetiresVirtualRoutes(transaction: Bool) async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let devices = [remappingRouterDevice(1), remappingRouterDevice(2)]
    for device in devices {
      await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
      try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    }
    harness.recorder.removeAll()
    harness.compatibility.rejectNeutral = true
    if transaction {
      await #expect(throws: RemappingOutputRoutingError.self) {
        _ = try await harness.router.beginProfileTransaction()
      }
      for device in devices {
        #expect(harness.recorder.snapshot().contains(.compatibilityStop(device)))
      }
    } else {
      await #expect(throws: RemappingOutputRoutingError.self) {
        try await harness.router.stopController(devices[0])
      }
      #expect(harness.recorder.snapshot().contains(.compatibilityStop(devices[0])))
    }
    harness.compatibility.rejectNeutral = false
    try await harness.router.shutdown()
  }

  @Test


  func shutdownRetiresVirtualBackendEvenWhenNeutralDeliveryFails() async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    harness.recorder.removeAll()
    harness.compatibility.rejectNeutral = true

    await #expect(throws: RemappingOutputRoutingError.self) { try await harness.router.shutdown() }
    #expect(harness.recorder.snapshot() == [.compatibilityStop(device)])
    harness.compatibility.rejectNeutral = false
    try await harness.router.shutdown()
    #expect(
      harness.recorder.snapshot() == [.compatibilityStop(device), .gamepad(.neutral, device)]
    )
  }

  @Test(arguments: [false, true])


  func virtualRouteRetiresAfterNeutralization(transaction: Bool) async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    harness.recorder.removeAll()
    if transaction {
      let pending = try await harness.router.beginProfileTransaction()
      #expect(
        harness.recorder.snapshot() == [.gamepad(.neutral, device), .compatibilityStop(device)]
      )
      try await harness.router.stopController(device)
      try await harness.router.rollBackProfileTransaction(pending)
      #expect(await harness.router.statuses().isEmpty)
    } else {
      try await harness.router.shutdown()
      try await harness.router.shutdown()
    }
    #expect(
      harness.recorder.snapshot() == [.gamepad(.neutral, device), .compatibilityStop(device)]
    )
  }

  @Test


  func outputSuppressionNeutralizesAndRestoresRemappedGamepad() async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)

    await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    #expect(
      harness.recorder.snapshot() == [.gamepad(RemappingGamepadState(buttons: [.north]), device)]
    )
    harness.router.suppressOutput = true
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)
    #expect(harness.recorder.snapshot().last == .gamepad(.neutral, device))
    harness.router.suppressOutput = false
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    #expect(
      harness.recorder.snapshot().last == .gamepad(RemappingGamepadState(buttons: [.north]), device)
    )
    try await harness.router.stopController(device)
  }

  @Test
  func virtualOnlyProfileDoesNotRequireSystemInputPostingAccess() async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    harness.access.set(.notAuthorized)
    await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
    try await harness.router.dispatchCausally(.activation, from: device)
    #expect(await harness.router.status(for: device)?.eligibility == .eligible)
    harness.foreground.set("com.example.Other")
    try await harness.router.refreshEligibility()
    #expect(await harness.router.status(for: device)?.eligibility == .targetApplicationNotFrontmost)
    #expect(harness.recorder.snapshot().isEmpty)
  }

  @Test


  func exclusiveProfileWaitsForOwnershipAndReleasesOnLoss() async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(physicalInput: .exclusive),
      bindings: original.bindings
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    #expect(harness.recorder.snapshot().isEmpty)

    #expect(await harness.router.status(for: device)?.eligibility == .physicalInputNotExclusive)
    await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    await harness.router.controllerInputOwnershipChanged(.shared, for: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)
    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
    #expect(await harness.router.status(for: device)?.eligibility == .physicalInputNotExclusive)
    await harness.router.controllerInputOwnershipChanged(.exclusive, for: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    #expect(harness.recorder.snapshot().last == .system(.keyDown(.space)))
    try await harness.router.stopController(device)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    #expect(await harness.router.status(for: device)?.eligibility == .physicalInputNotExclusive)
  }

  @Test
  func ownershipOfSameModelDoesNotAuthorizeAnotherController() async throws {
    let original = remappingRouterProfile()
    let profile = RemappingProfile(
      name: original.name,
      device: original.device,
      applicationScope: original.applicationScope,
      outputPolicy: RemappingOutputPolicy(physicalInput: .exclusive),
      bindings: original.bindings
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let first = remappingRouterDevice(1)
    let second = remappingRouterDevice(2)
    await harness.router.controllerInputOwnershipChanged(.exclusive, for: first)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: second)
    #expect(harness.recorder.snapshot().isEmpty)
    let transaction = try await harness.router.beginProfileTransaction()
    await harness.router.controllerInputOwnershipChanged(.accessDenied, for: first)
    try await harness.router.dispatchCausally(.activation, from: first)
    try await harness.router.acceptProfileTransaction(transaction)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: first)
    #expect(harness.recorder.snapshot().isEmpty)
    #expect(await harness.router.status(for: first)?.eligibility == .physicalInputNotExclusive)
  }

  @Test
  func activeProfileExclusivelyReplacesCompatibilityOutput() async throws {

    let profile = remappingRouterProfile()
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)

    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: mapped)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: compatibility)

    #expect(
      harness.recorder.snapshot() == [
        .system(.keyDown(.space)),
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceEast)]), compatibility),

      ]
    )
    #expect(
      await harness.router.status(for: mapped)?.selection == .remapping(profileID: profile.id)
    )
    #expect(await harness.router.status(for: compatibility)?.selection == .virtualGamepad)
  }

  @Test
  func routeTransitionsNeutralizeBeforeTheNewRouteEmits() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)
    let profile = remappingRouterProfile()
    try await harness.library.create(profile)
    try await harness.library.activate(profileID: profile.id)

    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    try await harness.library.deactivateAll(vendorID: 1118, productID: 654)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(changes: [.press(.faceWest)], from: device)

    #expect(
      harness.recorder.snapshot() == [
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceEast)]), device),
        .compatibilityStop(device), .system(.keyDown(.space)), .system(.keyUp(.space)),
        // A snapshot carries every held control, so compatibility sees East and South still held.
        .virtualGamepad(
          ControllerState.neutral.applying([
            .press(.faceEast), .press(.faceSouth), .press(.faceWest),
          ]),
          device
        ),
      ]
    )
  }

  @Test
  func sameModelControllersRetainExactIdentityAndAggregateHeldOutputs() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let first = remappingRouterDevice(1)
    let second = remappingRouterDevice(2)

    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: first)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: second)
    try await harness.router.stopController(first)
    try await harness.router.stopController(second)

    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
    #expect(await harness.router.status(for: first) == nil)
    #expect(await harness.router.status(for: second) == nil)
  }

  @Test
  func outputSuppressionTearsDownVirtualGamepadRouteBeforeReturning() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: compatibility)

    try await harness.router.setOutputSuppressed(true)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: compatibility)
    try await harness.router.setOutputSuppressed(true)

    #expect(
      harness.recorder.snapshot() == [
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceEast)]), compatibility),
        .compatibilityStop(compatibility),
      ]
    )
    #expect(
      await harness.router.status(for: compatibility)?.eligibility == .virtualOutputSuppressed
    )

    try await harness.router.setOutputSuppressed(false)
    #expect(await harness.router.status(for: compatibility)?.eligibility == .eligible)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: compatibility)
    #expect(
      Array(harness.recorder.snapshot().suffix(2)) == [
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceSouth)]), compatibility),
        .virtualGamepad(
          ControllerState.neutral.applying([.press(.faceSouth), .press(.faceEast)]),
          compatibility
        ),
      ]
    )
  }

}
