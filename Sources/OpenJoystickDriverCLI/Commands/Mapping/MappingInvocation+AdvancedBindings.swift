import Foundation
import OpenJoystickDriverKit

extension MappingInvocation {
  internal func chord(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.usage.chord", "Usage: map chord add|delete <profile> ...")
      )
    }
    switch action {
    case "add":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--sources", "--target", "--mode", "--window-ms"])
      let profile = try await resolve(selector, client: client)
      let sources = try MappingSyntax.sourceList(try options.required("--sources"))
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.addingChord(
        in: profile,
        sources: sources,
        destination: destination,
        mode: try MappingProfileEditor.chordMode(options),
        windowMs: try MappingProfileEditor.chordWindow(options)
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "delete":
      return try await deleteByID(client: client) { profile, id in
        try MappingProfileEditor.removingChord(from: profile, chordID: id)
      }
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.chord_action_unknown",
          "Unknown chord action '%@'. Expected: add | delete",
          action
        )
      )
    }
  }

  internal func sequence(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.usage.sequence",
          "Usage: map sequence add|delete <profile> ..."
        )
      )
    }
    switch action {
    case "add":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--sources", "--window", "--target"])
      let profile = try await resolve(selector, client: client)
      let sources = try MappingSyntax.sourceList(try options.required("--sources"))
      let window = try MappingSyntax.finiteDouble(
        try options.required("--window"),
        option: "--window"
      )
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.addingSequence(
        in: profile,
        sources: sources,
        windowMs: window,
        destination: destination
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "delete":
      return try await deleteByID(client: client) { profile, id in
        try MappingProfileEditor.removingSequence(from: profile, sequenceID: id)
      }
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.sequence_action_unknown",
          "Unknown sequence action '%@'. Expected: add | delete",
          action
        )
      )
    }
  }

  internal func layer(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.usage.layer",
          "Usage: map layer create|delete|bind|unbind|motion|list <profile> ..."
        )
      )
    }
    switch action {
    case "motion":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts, flags: ["--clear"])
      let tuningOptions = MappingProfileEditor.motionOptions.filter { $0.hasPrefix("--motion-") }
      try options.validate(allowed: Set(tuningOptions).union(["--layer", "--clear"]))
      let profile = try await resolve(selector, client: client)
      let id = try MappingSyntax.uuid(try options.required("--layer"), option: "--layer")
      let updated = try MappingProfileEditor.settingLayerMotion(
        profile,
        layerID: id,
        options: options
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "create":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--name", "--activator", "--mode"])
      let profile = try await resolve(selector, client: client)
      let name = try options.required("--name")
      let activator = try MappingSyntax.source(try options.required("--activator"))
      let mode = try layerMode(try options.required("--mode"))
      let updated = try MappingProfileEditor.creatingLayer(
        in: profile,
        name: name,
        activator: activator,
        mode: mode
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "delete":
      return try await deleteByID(client: client) { profile, id in
        try MappingProfileEditor.deletingLayer(from: profile, layerID: id)
      }
    case "bind":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts, flags: ["--invert"])
      try options.validate(
        allowed: Set(["--layer", "--source", "--target"]).union(Self.bindingOptions)
      )
      let profile = try await resolve(selector, client: client)
      let layerID = try MappingSyntax.uuid(try options.required("--layer"), option: "--layer")
      let source = try MappingSyntax.source(try options.required("--source"))
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.bindingInLayer(
        in: profile,
        layerID: layerID,
        source: source,
        destination: destination,
        options: options
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "unbind":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--layer", "--source"])
      let profile = try await resolve(selector, client: client)
      let layerID = try MappingSyntax.uuid(try options.required("--layer"), option: "--layer")
      let source = try MappingSyntax.source(try options.required("--source"))
      let updated = try MappingProfileEditor.unbindingInLayer(
        from: profile,
        layerID: layerID,
        source: source
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "list":
      let selector = try soleArgument(
        CLILocalized.text("cli.mapping.usage.layer_list", "map layer list <profile>")
      )
      let profile = try await resolve(selector, client: client)
      return MappingRenderer.layers(profile)
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_action_unknown",
          "Unknown layer action '%@'. Expected: create | delete | bind | unbind | motion | list",
          action
        )
      )
    }
  }
}
