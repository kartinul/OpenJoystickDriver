import Foundation
import OpenJoystickDriverKit

extension MappingProfileEditor {

  static func outputPolicy(
    _ options: MappingOptions,
    defaultValue: RemappingOutputPolicy = .systemInput
  ) throws -> RemappingOutputPolicy {
    let virtualRaw = options["--virtual-gamepad"] ?? defaultValue.virtualGamepad.rawValue
    let physicalRaw = options["--physical-input"] ?? defaultValue.physicalInput.rawValue
    guard let virtual = RemappingVirtualGamepadPolicy(rawValue: virtualRaw),
      let physical = RemappingPhysicalInputPolicy(rawValue: physicalRaw)
    else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.output_policy_invalid",
          """
          --virtual-gamepad: disabled|mapped|passthrough
          --physical-input: shared|exclusive
          """
        )
      )
    }
    return RemappingOutputPolicy(virtualGamepad: virtual, physicalInput: physical)
  }

  static func joyConPairSettings(
    _ options: MappingOptions,
    defaultValue: RemappingJoyConPairSettings? = nil
  ) throws -> RemappingJoyConPairSettings? {
    guard let raw = options["--joy-con-pair-gyro"] else { return defaultValue }
    if raw == "none" { return nil }
    guard let selection = RemappingJoyConGyroSelection(rawValue: raw) else {
      throw MappingCommandError.invalidArguments("--joy-con-pair-gyro: left|right|disabled|none")
    }
    return RemappingJoyConPairSettings(gyroSelection: selection)
  }

  static func applicationScope(
    _ options: MappingOptions,
    defaultValue: RemappingApplicationScope? = nil
  ) throws -> RemappingApplicationScope {
    let bundleID = options["--target-app"]
    let global = options.contains("--global")
    guard bundleID == nil || !global else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.scope_conflict",
          "Pass only one of --target-app or --global."
        )
      )
    }
    if let bundleID { return .application(bundleIdentifier: bundleID) }
    if global { return .global }
    guard let defaultValue else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.scope_required", "Pass one of --target-app or --global.")
      )
    }
    return defaultValue
  }

  /// Applies a shared Kit edit and reports a missing chord, sequence, or layer as a CLI error.
  internal static func edited(
    _ profile: RemappingProfile,
    _ edit: (inout RemappingProfile) throws -> Void
  ) throws -> RemappingProfile {
    var edited = profile
    do { try edit(&edited) } catch let error as RemappingProfileEditingError {
      throw MappingCommandError.invalidArguments(missingItemMessage(error))
    }
    return edited
  }

  private static func missingItemMessage(_ error: RemappingProfileEditingError) -> String {
    switch error {
    case .chordNotFound(let id):
      CLILocalized.format("cli.mapping.chord_missing", "No chord exists with ID %@.", id.uuidString)
    case .layerNotFound(let id):
      CLILocalized.format("cli.mapping.layer_missing", "No layer exists with ID %@.", id.uuidString)
    case .sequenceNotFound(let id):
      CLILocalized.format(
        "cli.mapping.sequence_missing",
        "No sequence exists with ID %@.",
        id.uuidString
      )
    }
  }
}
