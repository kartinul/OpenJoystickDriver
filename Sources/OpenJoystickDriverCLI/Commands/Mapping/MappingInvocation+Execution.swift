import Foundation
import OpenJoystickDriverKit

extension MappingInvocation {

  var isHelp: Bool { command == "help" || command == "--help" || command == "-h" }

  func execute(client: any MappingServiceClient) async throws -> String {
    switch command {
    case "help", "--help", "-h": return Self.help
    case "list": return try await renderSnapshot(client: client)
    case "show": return try await show(client: client)
    case "create": return try await create(client: client)
    case "restore-default-input": return try await restoreDefaultInput(client: client)
    case "clear-inputs": return try await clearInputs(client: client)
    case "update": return try await update(client: client)
    case "bind": return try await bind(client: client)
    case "unbind": return try await unbind(client: client)
    case "delete": return try await delete(client: client)
    case "import": return try await importProfile(client: client)
    case "export": return try await export(client: client)
    case "enable": return try await activate(client: client)
    case "disable": return try await deactivate(client: client)
    case "permission": return try await permission(client: client)
    case "calibration": return try await calibration(client: client)
    case "joy-con": return try await joyCon(client: client)
    case "chord": return try await chord(client: client)
    case "sequence": return try await sequence(client: client)
    case "layer": return try await layer(client: client)
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.command_unknown", "Unknown map command '%@'.", command)
      )
    }
  }

  internal func renderSnapshot(client: any MappingServiceClient) async throws -> String {
    let options = try MappingOptions(arguments, flags: ["--json"])
    try options.validate(allowed: ["--json"])
    let snapshot = try await client.snapshot()
    return try options.contains("--json")
      ? MappingRenderer.json(snapshot) : MappingRenderer.snapshot(snapshot)
  }

  internal func show(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--json"])
    try options.validate(allowed: ["--json"])
    let profile = try await resolve(selector, client: client)
    return try options.contains("--json")
      ? MappingRenderer.json(profile) : MappingRenderer.profile(profile)
  }

  internal func create(client: any MappingServiceClient) async throws -> String {
    let (name, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--global"])
    try options.validate(
      allowed: Set([

        "--vid", "--pid", "--target-app", "--global", "--virtual-gamepad", "--physical-input",
      ]).union(MappingProfileEditor.motionOptions).union(MappingProfileEditor.joyConPairOptions)
        .union(MappingProfileEditor.stickOptions).union(MappingProfileEditor.touchOptions).union(
          MappingProfileEditor.triggerOptions
        )
    )
    let profile = RemappingProfile(

      name: name,
      device: RemappingDeviceScope(
        vendorID: try MappingSyntax.identifier(options.required("--vid"), option: "--vid"),
        productID: try MappingSyntax.identifier(options.required("--pid"), option: "--pid")
      ),
      applicationScope: try MappingProfileEditor.applicationScope(options),
      outputPolicy: try MappingProfileEditor.outputPolicy(
        options,
        defaultValue: RemappingOutputPolicy(virtualGamepad: .passthrough)
      ),
      motionTuning: try MappingProfileEditor.motionTuning(options),
      gyroOutput: try MappingProfileEditor.gyroOutput(options),
      joyConPair: try MappingProfileEditor.joyConPairSettings(options),
      stickMappings: try MappingProfileEditor.stickMappings(options),
      triggerMappings: try MappingProfileEditor.triggerMappings(options),
      touchMappings: try MappingProfileEditor.touchMappings(options),
      bindings: []
    )
    try profile.validate()
    return render(try await client.create(profile), profileID: profile.id)
  }

  internal func update(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--global"])
    try options.validate(
      allowed: Set([
        "--name", "--vid", "--pid", "--target-app", "--global", "--virtual-gamepad",
        "--physical-input",
      ]).union(MappingProfileEditor.motionOptions).union(MappingProfileEditor.joyConPairOptions)
        .union(MappingProfileEditor.stickOptions).union(MappingProfileEditor.touchOptions).union(
          MappingProfileEditor.triggerOptions
        )
    )
    let profile = try await resolve(selector, client: client)
    let updated = try MappingProfileEditor.updating(profile, options: options)
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  internal func bind(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--invert"])
    try options.validate(allowed: Self.bindingOptions)
    let profile = try await resolve(selector, client: client)
    let updated = try MappingProfileEditor.replacingBinding(
      in: profile,
      source: try MappingSyntax.source(options.required("--source")),
      destination: try MappingSyntax.destination(options.required("--target")),
      options: options
    )
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  internal func unbind(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing)
    try options.validate(allowed: ["--source"])
    let profile = try await resolve(selector, client: client)
    let updated = try MappingProfileEditor.removingBinding(
      from: profile,
      source: try MappingSyntax.source(options.required("--source"))
    )
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  internal func delete(client: any MappingServiceClient) async throws -> String {
    let selector = try soleArgument(
      CLILocalized.text("cli.mapping.usage.delete", "map delete <uuid-or-name>")
    )
    let profile = try await resolve(selector, client: client)
    return MappingRenderer.snapshot(try await client.delete(id: profile.id))
  }

  internal func importProfile(client: any MappingServiceClient) async throws -> String {
    let path = try soleArgument(CLILocalized.text("cli.mapping.usage.import", "map import <file>"))
    let profile = try RemappingProfileFileStore.load(from: URL(fileURLWithPath: path))
    return render(try await client.importProfile(profile), profileID: profile.id)
  }

  internal func export(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing)
    try options.validate(allowed: ["--output"])
    let profile = try await resolve(selector, client: client)
    let text = try RemappingProfileFileStore.encodedJSON(profile)
    if let output = options["--output"] {
      try RemappingProfileFileStore.write(profile, to: URL(fileURLWithPath: output))
      return output
    }
    return text
  }

  internal func activate(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--allow-empty"])
    try options.validate(allowed: ["--allow-empty"])
    let profile = try await resolve(selector, client: client)
    guard !profile.suppressesAllControllerInput || options.contains("--allow-empty") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.empty_profile_requires_confirmation",
          "This profile suppresses all controller input. Pass --allow-empty to activate it."
        )
      )
    }
    return MappingRenderer.snapshot(try await client.activate(id: profile.id))
  }

  internal func restoreDefaultInput(client: any MappingServiceClient) async throws -> String {
    let selector = try soleArgument(
      CLILocalized.text(
        "cli.mapping.usage.restore_default_input",
        "map restore-default-input <uuid-or-name>"
      )
    )
    let profile = try await resolve(selector, client: client)
    let restored = profile.restoringDefaultInput()
    return render(
      try await client.update(restored, expectedCurrent: profile),
      profileID: profile.id
    )
  }

  internal func clearInputs(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--confirm"])
    try options.validate(allowed: ["--confirm"])
    guard options.contains("--confirm") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.clear_inputs_requires_confirmation",
          "Pass --confirm to clear all profile input configuration."
        )
      )
    }
    let profile = try await resolve(selector, client: client)
    let cleared = profile.clearingAllInput()
    return render(try await client.update(cleared, expectedCurrent: profile), profileID: profile.id)
  }

  internal func deactivate(client: any MappingServiceClient) async throws -> String {
    let options = try MappingOptions(arguments)
    try options.validate(allowed: ["--vid", "--pid", "--profile"])
    if let profileSelector = options["--profile"] {
      let profile = try await resolve(profileSelector, client: client)
      return MappingRenderer.snapshot(try await client.deactivate(profileID: profile.id))
    }
    let vendorID = try MappingSyntax.identifier(options.required("--vid"), option: "--vid")
    let productID = try MappingSyntax.identifier(options.required("--pid"), option: "--pid")
    return MappingRenderer.snapshot(
      try await client.deactivate(vendorID: vendorID, productID: productID)
    )
  }

  internal func permission(client: any MappingServiceClient) async throws -> String {
    let operation = try soleArgument(
      CLILocalized.text("cli.mapping.usage.permission", "map permission status|request")
    )
    guard operation == "status" || operation == "request" else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.usage.permission", "map permission status|request")
      )
    }
    return try await client.access(request: operation == "request").rawValue
  }

  internal func calibration(client: any MappingServiceClient) async throws -> String {
    guard let operation = arguments.first,
      operation == "status" || RemappingMotionCalibrationCommand(rawValue: operation) != nil
    else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.usage.calibration",
          "Usage: map calibration status|start|pause|reset --controller <runtime-identifier>"
        )
      )
    }
    let options = try MappingOptions(Array(arguments.dropFirst()))
    try options.validate(allowed: ["--controller"])
    let identifier = try options.required("--controller")
    guard !identifier.isEmpty, identifier.utf8.count <= 512 else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.calibration.identifier_required",
          "A valid controller runtime identifier is required."
        )
      )
    }
    return try MappingRenderer.json(
      await client.motionCalibration(
        runtimeIdentifier: identifier,
        command: RemappingMotionCalibrationCommand(rawValue: operation)
      )
    )
  }

  internal func joyCon(client: any MappingServiceClient) async throws -> String {
    guard let operation = arguments.first else {
      throw MappingCommandError.invalidArguments(
        "Usage: map joy-con pair <profile> --left <runtime-id> --right <runtime-id> | "
          + "unpair --session <uuid>"
      )
    }
    switch operation {
    case "pair":
      guard arguments.count >= 2 else {
        throw MappingCommandError.invalidArguments("A paired Joy-Con profile is required.")
      }
      let profile = try await resolve(arguments[1], client: client)
      let options = try MappingOptions(Array(arguments.dropFirst(2)))
      try options.validate(allowed: ["--left", "--right"])
      return MappingRenderer.snapshot(
        try await client.pairJoyCons(
          left: options.required("--left"),
          right: options.required("--right"),
          profileID: profile.id
        )
      )
    case "unpair":
      let options = try MappingOptions(Array(arguments.dropFirst()))
      try options.validate(allowed: ["--session"])
      let sessionID = try MappingSyntax.uuid(options.required("--session"), option: "--session")
      return MappingRenderer.snapshot(try await client.unpairJoyCons(sessionID: sessionID))
    default: throw MappingCommandError.invalidArguments("Expected joy-con pair or joy-con unpair.")
    }
  }

  internal func layerMode(_ raw: String) throws -> RemappingLayerActivation {
    guard let mode = RemappingLayerActivation(rawValue: raw) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.mode_invalid", "--mode must be 'hold' or 'toggle'.")
      )
    }
    return mode
  }
}
