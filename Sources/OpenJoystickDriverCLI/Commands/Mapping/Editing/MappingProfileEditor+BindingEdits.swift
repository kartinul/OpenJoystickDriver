import Foundation
import OpenJoystickDriverKit

extension MappingProfileEditor {
  static func replacingBinding(
    in profile: RemappingProfile,
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> RemappingProfile {
    let (axisTuning, turbo, longHold, doubleTap) = try resolvedBindingOptions(
      source: source,
      destination: destination,
      options: options
    )
    let existingID = profile.bindings.first { $0.source == source }?.id
    let replacement = RemappingBinding(
      id: existingID ?? UUID(),
      source: source,
      destination: destination,
      behavior: try behavior(
        options,
        fallback: profile.bindings.first { $0.source == source }?.behavior ?? .hold
      ),
      pulseDurationMs: try pulseDuration(
        options,
        existing: profile.bindings.first { $0.source == source }
      ),
      axisTuning: axisTuning,
      turbo: turbo,
      longHold: longHold,
      doubleTap: doubleTap,
      additionalActions: try additionalActions(
        options,
        fallback: profile.bindings.first { $0.source == source }?.additionalActions ?? []
      )
    )
    let updated = profile.replacing(
      bindings: profile.bindings.filter { $0.source != source } + [replacement]
    )
    try updated.validate()
    return updated
  }

  static func removingBinding(
    from profile: RemappingProfile,
    source: RemappingSource
  ) throws -> RemappingProfile {
    guard profile.bindings.contains(where: { $0.source == source }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.binding_missing",
          "No binding exists for the requested source."
        )
      )
    }
    let updated = profile.replacing(bindings: profile.bindings.filter { $0.source != source })
    try updated.validate()
    return updated
  }

  static func addingChord(
    in profile: RemappingProfile,
    sources: [RemappingSource],
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) throws -> RemappingProfile {
    try edited(profile) {
      try $0.addChord(
        sources: Set(sources),
        destination: destination,
        mode: mode,
        windowMs: windowMs
      )
    }
  }

  static func chordMode(_ options: MappingOptions) throws -> RemappingChordMode {
    let raw = options["--mode"] ?? "modifier"
    guard let mode = RemappingChordMode(rawValue: raw) else {
      throw MappingCommandError.invalidArguments("--mode: modifier|simultaneous")
    }
    return mode
  }

  static func chordWindow(_ options: MappingOptions) throws -> Double {
    try number(options["--window-ms"], option: "--window-ms", fallback: 50)
  }

  static func removingChord(
    from profile: RemappingProfile,
    chordID: UUID
  ) throws -> RemappingProfile { try edited(profile) { try $0.removeChord(chordID) } }

  static func addingSequence(
    in profile: RemappingProfile,
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws -> RemappingProfile {
    try edited(profile) {
      try $0.addSequence(sources: sources, windowMs: windowMs, destination: destination)
    }
  }

  static func removingSequence(
    from profile: RemappingProfile,
    sequenceID: UUID
  ) throws -> RemappingProfile { try edited(profile) { try $0.removeSequence(sequenceID) } }

  static func creatingLayer(
    in profile: RemappingProfile,
    name: String,
    activator: RemappingSource,
    mode: RemappingLayerActivation
  ) throws -> RemappingProfile {
    try edited(profile) { try $0.addLayer(name: name, activator: activator, activationMode: mode) }
  }

  static func deletingLayer(
    from profile: RemappingProfile,
    layerID: UUID
  ) throws -> RemappingProfile { try edited(profile) { try $0.removeLayer(layerID) } }

  static func settingLayerMotion(
    _ profile: RemappingProfile,
    layerID: UUID,
    options: MappingOptions
  ) throws -> RemappingProfile {
    guard let layer = profile.layers.first(where: { $0.id == layerID }) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_missing",
          "No layer exists with ID %@.",
          layerID.uuidString
        )
      )
    }
    let clear = options.contains("--clear")
    let supplied = motionOptions.filter { $0.hasPrefix("--motion-") }.contains(
      where: options.contains
    )
    guard clear != supplied else {
      throw MappingCommandError.invalidArguments("Pass motion options or --clear")
    }
    let tuning =
      clear
      ? nil : try motionTuning(options, defaultValue: layer.motionTuning ?? profile.motionTuning)
    return try edited(profile) { try $0.updateLayer(layerID, motionTuning: .some(tuning)) }
  }

  static func bindingInLayer(
    in profile: RemappingProfile,
    layerID: UUID,
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> RemappingProfile {
    let (axisTuning, turbo, longHold, doubleTap) = try resolvedBindingOptions(
      source: source,
      destination: destination,
      options: options
    )
    let existing = profile.layers.first { $0.id == layerID }?.bindings.first { $0.source == source }
    let binding = RemappingBinding(
      id: existing?.id ?? UUID(),
      source: source,
      destination: destination,
      behavior: try behavior(options, fallback: existing?.behavior ?? .hold),
      pulseDurationMs: try pulseDuration(options, existing: existing),
      axisTuning: axisTuning,
      turbo: turbo,
      longHold: longHold,
      doubleTap: doubleTap,
      additionalActions: try additionalActions(options, fallback: existing?.additionalActions ?? [])
    )
    return try edited(profile) { try $0.setLayerBinding(binding, in: layerID) }
  }

  static func unbindingInLayer(
    from profile: RemappingProfile,
    layerID: UUID,
    source: RemappingSource
  ) throws -> RemappingProfile {
    try edited(profile) { profile in
      let bindings = try profile.layer(layerID).bindings.filter { $0.source != source }
      try profile.updateLayer(layerID, bindings: bindings)
    }
  }

  static func updating(
    _ profile: RemappingProfile,
    options: MappingOptions
  ) throws -> RemappingProfile {
    let vendorID =
      try options["--vid"].map { try MappingSyntax.identifier($0, option: "--vid") }
      ?? profile.device.vendorID
    let productID =
      try options["--pid"].map { try MappingSyntax.identifier($0, option: "--pid") }
      ?? profile.device.productID
    let scope = try applicationScope(options, defaultValue: profile.applicationScope)
    let updated = profile.replacing(
      name: options["--name"] ?? profile.name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: scope,
      outputPolicy: try outputPolicy(options, defaultValue: profile.outputPolicy),
      motionTuning: try motionTuning(options, defaultValue: profile.motionTuning),
      gyroOutput: try gyroOutput(options, defaultValue: profile.gyroOutput),
      joyConPair: .some(try joyConPairSettings(options, defaultValue: profile.joyConPair)),
      stickMappings: try stickMappings(options, defaultValue: profile.stickMappings),
      triggerMappings: try triggerMappings(options, defaultValue: profile.triggerMappings),
      touchMappings: try touchMappings(options, defaultValue: profile.touchMappings)
    )
    try updated.validate()
    return updated
  }
}
