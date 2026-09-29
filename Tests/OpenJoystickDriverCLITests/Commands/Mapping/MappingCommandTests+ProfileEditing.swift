import Foundation
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

extension MappingCommandTests {
  @Test
  func stickCommandsCreatePreserveRemoveAndRejectInvalidEdits() async throws {
    let creator = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Flick", "--vid", "1", "--pid", "2", "--global", "--stick-source", "right",
      "--stick-mode", "flick", "--stick-pointer-points-per-degree", "4",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    #expect(
      profile.stickMappings == [
        RemappingStickMapping(source: .right, mode: .flick, pointerPointsPerDegree: 4)
      ]
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--name", "Renamed",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.stickMappings == profile.stickMappings)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: RemappingStickMappingError.invalidField("flick_duration_ms")) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--stick-source", "right", "--stick-flick-duration-ms",
        "-1",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--stick-source", "right", "--stick-mode", "none",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.stickMappings.isEmpty == true)
    #expect(await client.lastExpectedCurrent == profile)
  }

  @Test
  func motionOptionsReachCreateAndValidatedUpdate() async throws {
    let createClient = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Motion", "--vid", "1118", "--pid", "654", "--global", "--motion-space", "world",
      "--motion-pitch-sensitivity", "3", "--motion-invert-yaw", "true",
      "--motion-smoothing-half-time-ms", "25",
    ]).execute(client: createClient)
    let original = try #require(await createClient.submittedProfile)
    #expect(original.motionTuning.space == .world)
    #expect(original.motionTuning.pitchSensitivity == 3)
    #expect(original.motionTuning.invertYaw)
    let client = MockMappingClient(snapshotValue: snapshot([original]))
    _ = try await MappingInvocation(arguments: [
      "update", original.id.uuidString, "--motion-invert-yaw", "false", "--motion-yaw-sensitivity",
      "4",
    ]).execute(client: client)
    let updated = try #require(await client.submittedProfile)
    #expect(updated.motionTuning.space == .world)
    #expect(updated.motionTuning.pitchSensitivity == 3)
    #expect(updated.motionTuning.smoothingHalfTimeMs == 25)
    #expect(updated.motionTuning.yawSensitivity == 4)
    #expect(!updated.motionTuning.invertYaw)
    #expect(await client.lastExpectedCurrent == original)
    await #expect(throws: RemappingMotionTuningError.invalidField("yaw_sensitivity")) {
      try await MappingInvocation(arguments: [
        "update", original.id.uuidString, "--motion-yaw-sensitivity", "101",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
  }

  @Test
  func bindingBehaviorCanBeAuthoredAndInvalidValuesDoNotMutate() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "bind", profile.id.uuidString, "--source", "button:south", "--target", "key:space",
      "--behavior", "toggle",
    ]).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.bindings.first?.behavior == .toggle)
    let preserved = try MappingProfileEditor.replacingBinding(
      in: submitted,
      source: .button(.south),
      destination: .mouseButton(.left),
      options: MappingOptions([])
    )
    #expect(preserved.bindings.first?.behavior == .toggle)
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "bind", profile.id.uuidString, "--source", "button:south", "--target", "key:space",
        "--behavior", "invalid",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
  }

  @Test
  func applicationScopeAndDeviceIdentifiersAreEditable() throws {
    let profile = makeProfile()
    let options = try MappingOptions([
      "--vid", "0x054c", "--pid", "3302", "--target-app", "com.example.Game",
    ])
    let updated = try MappingProfileEditor.updating(profile, options: options)
    #expect(updated.device.vendorID == 1356)
    #expect(updated.device.productID == 3302)
    #expect(updated.applicationScope == .application(bundleIdentifier: "com.example.Game"))
  }

  @Test
  func allAxisFieldsAndGainAreApplied() throws {
    let options = try MappingOptions(
      [
        "--deadzone", "0.2", "--gain", "1.5", "--invert", "--response-curve", "smooth_step",
        "--digital-threshold", "0.7", "--source", "axis:left_stick_x", "--target", "move:x",
      ],
      flags: ["--invert"]
    )
    let updated = try MappingProfileEditor.replacingBinding(
      in: makeProfile(),
      source: .axis(.leftStickX),
      destination: .mouseMovement(.x),
      options: options
    )
    let tuning = try #require(updated.bindings.first?.axisTuning)
    #expect(tuning.deadzone == 0.2)
    #expect(tuning.gain == 1.5)
    #expect(tuning.inverted)
    #expect(tuning.responseCurve == .smoothStep)
    #expect(tuning.digitalActivationThreshold == 0.7)
  }

  @Test
  func turboRequiresPairAndRejectsContinuousOutputs() throws {
    let partial = try MappingOptions(["--turbo-rate", "20"])
    #expect(throws: MappingCommandError.self) {
      try MappingProfileEditor.replacingBinding(
        in: makeProfile(),
        source: .button(.south),
        destination: .keyboard(key: .space, modifiers: []),
        options: partial
      )
    }
    let complete = try MappingOptions(["--turbo-rate", "20", "--turbo-duty", "0.4"])
    let updated = try MappingProfileEditor.replacingBinding(
      in: makeProfile(),
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: []),
      options: complete
    )
    #expect(updated.bindings.first?.turbo == RemappingTurbo(repeatRateHz: 20, dutyCycle: 0.4))
    #expect(throws: MappingCommandError.self) {
      try MappingProfileEditor.replacingBinding(
        in: makeProfile(),
        source: .axis(.leftStickX),
        destination: .scroll(.x),
        options: complete
      )
    }
  }

  @Test
  func replacePreservesIdentityAndUnbindRemovesIt() throws {
    let bindingID = UUID()
    let profile = makeProfile(bindings: [
      RemappingBinding(
        id: bindingID,
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: [])
      )
    ])
    let replaced = try MappingProfileEditor.replacingBinding(
      in: profile,
      source: .button(.south),
      destination: .mouseButton(.left),
      options: MappingOptions([])
    )
    #expect(replaced.bindings.first?.id == bindingID)
    #expect(
      try MappingProfileEditor.removingBinding(from: replaced, source: .button(.south)).bindings
        .isEmpty
    )
  }

  @Test
  func replacingALayerBindingPreservesItsIdentity() throws {
    let bindingID = UUID()
    let binding = RemappingBinding(
      id: bindingID,
      source: .button(.south),
      destination: .keyboard(key: .a, modifiers: [])
    )
    let layer = RemappingLayer(
      name: "Aim",
      activationMode: .hold,
      activator: .button(.east),
      bindings: [binding]
    )
    let profile = makeProfile().replacing(layers: [layer])
    let replaced = try MappingProfileEditor.bindingInLayer(
      in: profile,
      layerID: layer.id,
      source: .button(.south),
      destination: .mouseButton(.left),
      options: MappingOptions([])
    )
    #expect(replaced.layers.first?.bindings.map(\.id) == [bindingID])
  }

  @Test
  func repeatedUnknownAndMalformedOptionsAreRejectedBeforeRPC() async throws {
    #expect(throws: MappingCommandError.self) { try MappingOptions(["--vid", "1", "--vid", "2"]) }
    let client = MockMappingClient(snapshotValue: snapshot([makeProfile()]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["create", "Test", "--unknown", "x"]).execute(
        client: client
      )
    }
    #expect(await client.mutationCount == 0)
  }

  @Test
  func obsoleteMappingAliasesAreRejectedBeforeRPC() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["status"]).execute(client: client)
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "bind", profile.id.uuidString, "--source", "axis:left_stick_x", "--target", "move:x",
        "--sensitivity", "1.5",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 0)
  }

  @Test
  func helpIsRecognizedAndRenderedWithoutAServiceOperation() async throws {
    let invocation = try MappingInvocation(arguments: ["--help"])
    let client = MockMappingClient(snapshotValue: snapshot([]))

    #expect(invocation.isHelp)
    #expect(try await invocation.execute(client: client) == MappingInvocation.help)
    #expect(await client.mutationCount == 0)
  }

  @Test
  func selectorsDistinguishUUIDMissingAndAmbiguousNames() async throws {
    let first = makeProfile(name: "Same")
    let second = makeProfile(name: "same")
    let client = MockMappingClient(snapshotValue: snapshot([first, second]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["show", "Same"]).execute(client: client)
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["show", "Missing"]).execute(client: client)
    }
    let byID = try await MappingInvocation(arguments: ["show", first.id.uuidString]).execute(
      client: client
    )
    #expect(byID.contains(first.id.uuidString))
  }

  @Test
  func jsonIsPrettySortedAndDeterministic() throws {
    let profile = makeProfile(name: "JSON")
    let first = try MappingRenderer.json(profile)
    #expect(first == (try MappingRenderer.json(profile)))
    #expect(first.contains("\n  \"applicationScope\""))
    let keys = try #require(JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
    #expect(keys["name"] as? String == "JSON")
  }

  @Test
  func mutationAndPermissionCommandsRouteThroughInjectedClient() async throws {
    let profile = makeProfile(name: "Desktop")
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let commands = [
      ["create", "New", "--vid", "1118", "--pid", "654", "--global"],
      ["update", profile.id.uuidString, "--name", "Renamed"],
      ["bind", profile.id.uuidString, "--source", "button:south", "--target", "key:a"],
      ["delete", profile.id.uuidString], ["enable", profile.id.uuidString],
      ["disable", "--vid", "1118", "--pid", "654"],
    ]
    for arguments in commands {
      _ = try await MappingInvocation(arguments: arguments).execute(client: client)
    }
    #expect(
      try await MappingInvocation(arguments: ["permission", "status"]).execute(client: client)
        == "granted"
    )
    #expect(
      try await MappingInvocation(arguments: ["permission", "request"]).execute(client: client)
        == "granted"
    )
    #expect(await client.mutationCount == commands.count)
  }

  @Test
  func staleUpdateConflictIsPropagatedWithoutRetryOrOverwrite() async throws {
    let profile = makeProfile(name: "Desktop")
    let conflict = ApplicationServiceRemappingRPCError(
      code: .profileUpdateConflict,
      message: "The profile changed since it was read."
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]), updateError: conflict)

    await #expect(throws: conflict) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--name", "Stale edit",
      ]).execute(client: client)
    }

    #expect(await client.updateAttempts == 1)
    #expect(await client.lastExpectedCurrent == profile)
    #expect(client.snapshotValue.profiles == [profile])
  }

  @Test
  func editBindAndUnbindPassTheExactProfileTheyRead() async throws {
    let profile = makeProfile(
      name: "Desktop",
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let commands = [
      ["update", profile.id.uuidString, "--name", "Renamed"],
      [
        "bind", profile.id.uuidString, "--source", "axis:left_stick_x", "--target", "move:x",
        "--deadzone", "0.2",
      ], ["unbind", profile.id.uuidString, "--source", "button:south"],
    ]

    for arguments in commands {
      _ = try await MappingInvocation(arguments: arguments).execute(client: client)
    }

    #expect(await client.expectedProfiles == [profile, profile, profile])
  }

}
