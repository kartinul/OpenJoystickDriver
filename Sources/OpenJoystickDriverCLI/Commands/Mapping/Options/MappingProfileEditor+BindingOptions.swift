import Foundation
import OpenJoystickDriverKit

extension MappingProfileEditor {
  internal static func behavior(
    _ options: MappingOptions,
    fallback: RemappingBindingBehavior
  ) throws -> RemappingBindingBehavior {
    guard let raw = options["--behavior"] else { return fallback }
    guard let value = RemappingBindingBehavior(rawValue: raw) else {
      throw MappingCommandError.invalidArguments(
        "--behavior: hold|toggle|tap_on_press|tap_on_release|pulse|press|release"
      )
    }
    return value
  }

  internal static func additionalActions(
    _ options: MappingOptions,
    fallback: [RemappingAction]
  ) throws -> [RemappingAction] {
    guard let raw = options["--actions-json"] else { return fallback }
    guard raw.utf8.count <= RemappingProfile.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(raw.utf8.count)
    }
    return try JSONDecoder().decode([RemappingAction].self, from: Data(raw.utf8))
  }

  internal static func pulseDuration(
    _ options: MappingOptions,
    existing: RemappingBinding?
  ) throws -> Double {
    let selected = try behavior(options, fallback: existing?.behavior ?? .hold)
    let fallback =
      selected == .pulse
      ? existing?.pulseDurationMs ?? RemappingBinding.defaultPulseDurationMs
      : RemappingBinding.defaultPulseDurationMs
    return try number(options["--pulse-ms"], option: "--pulse-ms", fallback: fallback)
  }

  internal static func resolvedBindingOptions(
    source: RemappingSource,
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> (RemappingAxisTuning?, RemappingTurbo?, RemappingLongHold?, RemappingDoubleTap?) {
    (
      try tuning(source: source, options: options),
      try turbo(destination: destination, options: options), try longHold(options: options),
      try doubleTap(options: options)
    )
  }

  internal static func tuning(
    source: RemappingSource,
    options: MappingOptions
  ) throws -> RemappingAxisTuning? {
    let tuningOptions = [
      "--deadzone", "--gain", "--invert", "--response-curve", "--digital-threshold",
    ]
    let supplied = tuningOptions.contains(where: options.contains)
    let isAxis =
      switch source {
      case .axis, .axisDirection: true
      default: false
      }
    guard isAxis || !supplied else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.axis_options_source", "Axis options require an axis source.")
      )
    }
    guard isAxis else { return nil }
    return RemappingAxisTuning(
      deadzone: try number(options["--deadzone"], option: "--deadzone", fallback: 0.1),
      gain: try number(options["--gain"], option: "--gain", fallback: 1),
      inverted: options.contains("--invert"),
      responseCurve: try curve(options["--response-curve"]),
      digitalActivationThreshold: try number(
        options["--digital-threshold"],
        option: "--digital-threshold",
        fallback: 0.5
      )
    )
  }

  internal static func turbo(
    destination: RemappingDestination,
    options: MappingOptions
  ) throws -> RemappingTurbo? {
    let rate = options["--turbo-rate"]
    let duty = options["--turbo-duty"]
    guard rate != nil || duty != nil else { return nil }
    guard let rate, let duty else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.turbo_pair",
          "--turbo-rate and --turbo-duty must be supplied together."
        )
      )
    }
    guard destination.acceptsTurbo else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.turbo_unsupported",
          "Turbo is not supported for pointer movement or scrolling."
        )
      )
    }
    return RemappingTurbo(
      repeatRateHz: try MappingSyntax.finiteDouble(rate, option: "--turbo-rate"),
      dutyCycle: try MappingSyntax.finiteDouble(duty, option: "--turbo-duty")
    )
  }

  internal static func longHold(options: MappingOptions) throws -> RemappingLongHold? {
    guard let raw = options["--long-hold"] else { return nil }
    let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(
      String.init
    )
    guard parts.count == 2 else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.long_hold_format",
          "--long-hold expects <ms>:<target>, e.g. --long-hold 500:key:b"
        )
      )
    }
    let duration = try MappingSyntax.finiteDouble(parts[0], option: "--long-hold duration")
    let destination = try MappingSyntax.destination(parts[1])
    return RemappingLongHold(durationMs: duration, destination: destination)
  }

  internal static func doubleTap(options: MappingOptions) throws -> RemappingDoubleTap? {
    guard let raw = options["--double-tap"] else { return nil }
    let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(
      String.init
    )
    guard parts.count == 2 else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.double_tap_format",
          "--double-tap expects <ms>:<target>, e.g. --double-tap 300:key:c"
        )
      )
    }
    let window = try MappingSyntax.finiteDouble(parts[0], option: "--double-tap window")
    let destination = try MappingSyntax.destination(parts[1])
    return RemappingDoubleTap(windowMs: window, destination: destination)
  }

  internal static func number(_ raw: String?, option: String, fallback: Double) throws -> Double {
    guard let raw else { return fallback }
    return try MappingSyntax.finiteDouble(raw, option: option)
  }

  internal static func curve(_ raw: String?) throws -> RemappingResponseCurve {
    guard let raw else { return .linear }
    guard let value = RemappingResponseCurve(rawValue: raw) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.curve_unknown", "Unknown response curve '%@'.", raw)
      )
    }
    return value
  }

}
