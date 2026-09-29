import Foundation
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

extension MappingCommandTests {
  @Test(arguments: [
    ("button:south", RemappingSource.button(.south)), ("dpad:left", RemappingSource.dpad(.left)),
    ("axis:left_stick_x", RemappingSource.axis(.leftStickX)),
    ("axis:right_trigger:positive", RemappingSource.axisDirection(.rightTrigger, .positive)),
    ("trigger:left:soft", RemappingSource.triggerStage(.left, .soft)),
    ("trigger:right:full", RemappingSource.triggerStage(.right, .full)),
    ("motion:lean:left", RemappingSource.motionLean(.left)),
    ("motion:lean:right", RemappingSource.motionLean(.right)),
    ("touch:left:contact", RemappingSource.touchContact(.left)),
    (
      "touch:right:grid:2:3:1:2",
      RemappingSource.touchGrid(
        RemappingTouchGridSource(surface: .right, columns: 2, rows: 3, column: 1, row: 2)
      )
    ),
    (
      "touch:primary:swipe:left:0.25",
      RemappingSource.touchSwipe(
        RemappingTouchSwipeSource(surface: .primary, direction: .left, minimumDistance: 0.25)
      )
    ),
  ])
  func parsesEverySourceFamily(raw: String, expected: RemappingSource) throws {
    #expect(try MappingSyntax.source(raw) == expected)
  }

  @Test
  func touchOptionsAndSourcesReachCreateUpdateAndRendering() async throws {
    let createClient = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Touch", "--vid", "1", "--pid", "2", "--global", "--virtual-gamepad", "mapped",
      "--touch-surface", "right", "--touch-mode", "right_stick", "--touch-stick-radius", "0.4",
    ]).execute(client: createClient)
    let created = try #require(await createClient.submittedProfile)
    #expect(created.touchMappings.first?.mode == .rightStick)
    #expect(created.touchMappings.first?.stickRadius == 0.4)

    let updateClient = MockMappingClient(snapshotValue: snapshot([created]))
    _ = try await MappingInvocation(arguments: [
      "update", created.id.uuidString, "--touch-surface", "right", "--touch-mode", "pointer",
      "--touch-pointer-sensitivity", "900",
    ]).execute(client: updateClient)
    let updated = try #require(await updateClient.submittedProfile)
    #expect(updated.touchMappings.first?.mode == .pointer)
    #expect(updated.touchMappings.first?.pointerSensitivity == 900)

    let bindClient = MockMappingClient(snapshotValue: snapshot([updated]))
    _ = try await MappingInvocation(arguments: [
      "bind", updated.id.uuidString, "--source", "touch:right:grid:3:2:2:1", "--target",
      "key:space",
    ]).execute(client: bindClient)
    let bound = try #require(await bindClient.submittedProfile)
    #expect(MappingRenderer.profile(bound).contains("touch:right:grid:3:2:2:1"))
    #expect(MappingRenderer.profile(bound).contains("touch:right mode:pointer"))
  }

  @Test(arguments: [
    ("key:a", RemappingDestination.keyboard(key: .a, modifiers: [])),
    ("mouse:forward", RemappingDestination.mouseButton(.forward)),
    ("move:x", RemappingDestination.mouseMovement(.x)),
    ("scroll:y", RemappingDestination.scroll(.y)),
  ])
  func parsesEveryDestinationFamily(raw: String, expected: RemappingDestination) throws {
    #expect(try MappingSyntax.destination(raw) == expected)
  }

  @Test(arguments: ["chord", "sequence", "layer"])
  func nestedCommandsResolveProfileAfterAction(command: String) async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let options: [String]
    if command == "layer" {
      options = ["--name", "Layer", "--activator", "button:west", "--mode", "hold"]
    } else {
      options =
        ["--sources", "button:south,button:east", "--target", "key:space"]
        + (command == "sequence" ? ["--window", "200"] : [])
    }
    _ = try await MappingInvocation(
      arguments: [command, command == "layer" ? "create" : "add", profile.id.uuidString] + options
    ).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.id == profile.id)
    #expect(await client.lastExpectedCurrent == profile)
    #expect(submitted.chords.count + submitted.sequences.count + submitted.layers.count == 1)
  }

  @Test
  func layerMotionCommandPersistsOverrideAndRejectsInvalidMutation() async throws {
    let initial = makeProfile()
    let creator = MockMappingClient(snapshotValue: snapshot([initial]))
    _ = try await MappingInvocation(arguments: [
      "layer", "create", initial.id.uuidString, "--name", "Aim", "--activator", "button:west",
      "--mode", "hold",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    let layer = try #require(profile.layers.first)
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let prefix = ["layer", "motion", profile.id.uuidString, "--layer", layer.id.uuidString]
    _ = try await MappingInvocation(arguments: prefix + ["--motion-yaw-sensitivity", "0.5"])
      .execute(client: client)
    let edited = try #require(await client.submittedProfile)
    #expect(edited.layers.first?.motionTuning?.yawSensitivity == 0.5)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: RemappingMotionTuningError.self) {
      try await MappingInvocation(arguments: prefix + ["--motion-yaw-sensitivity", "-1"]).execute(
        client: client
      )
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: prefix + ["--clear", "--motion-yaw-sensitivity", "2"])
        .execute(client: client)
    }
    #expect(await client.mutationCount == 1)
    let clearer = MockMappingClient(snapshotValue: snapshot([edited]))
    _ = try await MappingInvocation(arguments: prefix + ["--clear"]).execute(client: clearer)
    #expect(await clearer.submittedProfile?.layers.first?.motionTuning == nil)
    #expect(await clearer.lastExpectedCurrent == edited)
  }

  @Test
  func simultaneousChordOptionsReachValidatedProfile() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let arguments = [
      "chord", "add", profile.id.uuidString, "--sources", "button:south,button:east", "--target",
      "key:space", "--mode", "simultaneous", "--window-ms",
    ]
    _ = try await MappingInvocation(arguments: arguments + ["75"]).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.chords.first?.mode == .simultaneous)
    #expect(submitted.chords.first?.windowMs == 75)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: RemappingValidationError.chordWindowOutOfRange(index: 0)) {
      try await MappingInvocation(arguments: arguments + ["0"]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
  }

  @Test
  func parsesAndCanonicallyRendersModifiers() throws {
    let destination = try MappingSyntax.destination("key:f1:mods=shift,command,option,control")
    #expect(MappingRenderer.destination(destination) == "key:f1:mods=command,control,option,shift")
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.destination("key:a:mods=shift,shift")
    }
  }

  @Test(arguments: ["status", "start", "pause", "reset"])
  func calibrationSelectsExactControllerAndPropagatesServiceErrors(operation: String) async throws {
    let client = MockMappingClient(snapshotValue: snapshot([]))
    let identifier = "045e:028e:location:2"
    await #expect(
      throws: ApplicationServiceRemappingRPCError(code: .controllerUnavailable, message: identifier)
    ) {
      try await MappingInvocation(arguments: ["calibration", operation, "--controller", identifier])
        .execute(client: client)
    }
    #expect(await client.calibrationCalls == 1)
    #expect(
      await client.calibrationCommand == RemappingMotionCalibrationCommand(rawValue: operation)
    )
    #expect(await client.mutationCount == 0)
  }

  @Test
  func malformedCalibrationCommandsDoNotReachService() async throws {
    let client = MockMappingClient(snapshotValue: snapshot([]))
    for arguments in [
      ["calibration"], ["calibration", "stop"], ["calibration", "start"],
      ["calibration", "start", "--controller", ""],
      ["calibration", "start", "--controller", String(repeating: "é", count: 257)],
      ["calibration", "start", "--controller", "one", "--unknown", "value"],
    ] {
      await #expect(throws: MappingCommandError.self) {
        try await MappingInvocation(arguments: arguments).execute(client: client)
      }
    }
    #expect(await client.calibrationCalls == 0)
  }

  @Test
  func nestedLayerBindingAcceptsActionCollection() async throws {
    let initial = makeProfile()
    let createClient = MockMappingClient(snapshotValue: snapshot([initial]))
    _ = try await MappingInvocation(arguments: [
      "layer", "create", initial.id.uuidString, "--name", "Layer", "--activator", "button:west",
      "--mode", "hold",
    ]).execute(client: createClient)
    let profile = try #require(await createClient.submittedProfile)
    let layer = try #require(profile.layers.first)
    let actions = [RemappingAction(destination: .keyboard(key: .b, modifiers: []))]
    let json = try #require(String(data: JSONEncoder().encode(actions), encoding: .utf8))
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "layer", "bind", profile.id.uuidString, "--layer", layer.id.uuidString, "--source",
      "button:south", "--target", "key:a", "--actions-json", json,
    ]).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.layers.first?.bindings.first?.additionalActions == actions)
    #expect(await client.lastExpectedCurrent == profile)
    _ = try await MappingInvocation(arguments: ["layer", "list", profile.id.uuidString]).execute(
      client: client
    )
    #expect(await client.mutationCount == 1)
  }

  @Test
  func numericIdentifiersAcceptDecimalAndPrefixedHexOnly() throws {
    #expect(try MappingSyntax.identifier("1118", option: "--vid") == 1118)
    #expect(try MappingSyntax.identifier("0x045e", option: "--vid") == 1118)
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.identifier("045e", option: "--vid")
    }
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.identifier("65536", option: "--vid")
    }
  }

  @Test
  func outputPolicyOptionsReachCreateAndUpdate() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "create", "Virtual", "--vid", "1118", "--pid", "654", "--global", "--virtual-gamepad",
      "passthrough", "--physical-input", "exclusive",
    ]).execute(client: client)
    #expect(
      await client.submittedProfile?.outputPolicy
        == RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .exclusive)
    )
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--virtual-gamepad", "mapped",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.outputPolicy.virtualGamepad == .mapped)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--virtual-gamepad", "invalid",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 2)
  }

  @Test
  func newProfilesPassThroughAndEmptyProfilesRequireExplicitCommands() async throws {
    let creator = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Default", "--vid", "1", "--pid", "2", "--global",
    ]).execute(client: creator)
    #expect(await creator.submittedProfile?.outputPolicy.virtualGamepad == .passthrough)

    let empty = RemappingProfile(
      name: "Empty",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: []
    )
    let client = MockMappingClient(snapshotValue: snapshot([empty]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["enable", empty.id.uuidString]).execute(
        client: client
      )
    }
    #expect(await client.mutationCount == 0)
    _ = try await MappingInvocation(arguments: ["enable", empty.id.uuidString, "--allow-empty"])
      .execute(client: client)
    #expect(await client.mutationCount == 1)

    _ = try await MappingInvocation(arguments: ["restore-default-input", empty.id.uuidString])
      .execute(client: client)
    #expect(await client.submittedProfile?.outputPolicy.virtualGamepad == .passthrough)

    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["clear-inputs", empty.id.uuidString]).execute(
        client: client
      )
    }
    #expect(await client.mutationCount == 2)
    _ = try await MappingInvocation(arguments: ["clear-inputs", empty.id.uuidString, "--confirm"])
      .execute(client: client)
    #expect(await client.submittedProfile?.suppressesAllControllerInput == true)
  }

  @Test
  func gyroOptionsCreatePreserveAndRejectInvalidUpdates() async throws {
    let creator = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Gyro", "--vid", "1", "--pid", "2", "--global", "--gyro-output", "mouse",
      "--gyro-pointer-points-per-degree", "4.5", "--gyro-activation", "toggle",
      "--gyro-activation-source", "button:south",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    #expect(profile.gyroOutput.mode == .mouse)
    #expect(profile.gyroOutput.pointerPointsPerDegree == 4.5)
    #expect(profile.gyroOutput.activationMode == .toggle)

    #expect(profile.gyroOutput.activationSource == .button(.south))
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--name", "Renamed",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.gyroOutput == profile.gyroOutput)

    await #expect(throws: RemappingGyroOutputError.invalidField("pointer_points_per_degree")) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--gyro-pointer-points-per-degree", "-1",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
    #expect(await client.lastExpectedCurrent == profile)
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--gyro-activation", "always",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.gyroOutput.activationMode == .always)
    #expect(await client.submittedProfile?.gyroOutput.activationSource == nil)
  }

}
