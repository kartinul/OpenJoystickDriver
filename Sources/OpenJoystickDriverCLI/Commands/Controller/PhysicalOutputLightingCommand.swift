import Foundation
import OpenJoystickDriverKit

extension PhysicalOutputCommand {
  internal func plan(arguments: [String]) async throws {
    let parsed = try parseDeviceOption(arguments)
    let values = parsed.arguments
    guard values.count == 2 else {
      printHelp()
      throw CLIExit.failure
    }
    let vendorID = try parseIdentifier(values[0], label: "VID")
    let productID = try parseIdentifier(values[1], label: "PID")
    let device = try await requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    let plan = PhysicalOutputValidationPlan(device: device)
    print(
      CLILocalized.format(
        "cli.controller.outputPlan",
        "Physical output validation plan for %@:%@",
        hex(vendorID),
        hex(productID)
      )
    )
    if plan.steps.isEmpty {
      print(
        CLILocalized.text(
          "cli.controller.noOutputSteps",
          "No source-backed physical output steps are available."
        )
      )
    }
    for (index, step) in plan.steps.enumerated() {
      print("\(index + 1). \(step.id)")
      print(CLILocalized.format("cli.controller.planRun", "   Run: %@", step.command))
      print(
        CLILocalized.format("cli.controller.planExpect", "   Expect: %@", step.expectedObservation)
      )
    }
    for note in plan.notes {
      print(CLILocalized.format("cli.controller.planNote", "Note: %@", note))
    }
  }

  internal func color(arguments: [String]) async throws {
    let parsed = try parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 5 else {
      printHelp()
      throw CLIExit.failure
    }
    let vendorID = try parseIdentifier(arguments[0], label: "VID")
    let productID = try parseIdentifier(arguments[1], label: "PID")
    let components = try zip(["red", "green", "blue"], arguments.dropFirst(2)).map { label, value in
      let parsed = try parseInteger(value, label: label)
      guard (0...255).contains(parsed) else {
        try fail(
          CLILocalized.text("cli.controller.colorRange", "Color components must be 0...255.")
        )
      }
      return UInt8(parsed)
    }

    let device = try await requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    try await sendOutput(
      .setRGB(ControllerColor(red: components[0], green: components[1], blue: components[2])),
      to: device,
      unsupported: Message(
        key: "cli.controller.noRGB",
        english: "The selected controller has no source-backed RGB implementation."
      ),
      failed: Message(
        key: "cli.controller.rgbFailed",
        english: "The application service could not set physical RGB color."
      )
    )
    print(
      CLILocalized.format(
        "cli.controller.rgbSet",
        "Physical RGB color set on %@:%@.",
        hex(vendorID),
        hex(productID)
      )
    )
  }

  internal func brightness(arguments: [String]) async throws {
    let parsed = try parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 3 else {
      printHelp()
      throw CLIExit.failure
    }
    let vendorID = try parseIdentifier(arguments[0], label: "VID")
    let productID = try parseIdentifier(arguments[1], label: "PID")
    let rawBrightness = try parseInteger(arguments[2], label: "brightness")
    guard (0...255).contains(rawBrightness) else {
      try fail(CLILocalized.text("cli.controller.brightnessRange", "Brightness must be 0...255."))
    }

    let device = try await requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    try await sendOutput(
      .setLightBrightness(UnipolarValue(byte: UInt8(rawBrightness))),
      to: device,
      unsupported: Message(
        key: "cli.controller.noBrightness",
        english: "The selected controller has no source-backed brightness implementation."
      ),
      failed: Message(
        key: "cli.controller.brightnessFailed",
        english: "The application service could not set physical LED brightness."
      )
    )
    print(
      CLILocalized.format(
        "cli.controller.brightnessSet",
        "Physical LED brightness set on %@:%@.",
        hex(vendorID),
        hex(productID)
      )
    )
  }
}
