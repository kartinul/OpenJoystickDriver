import Foundation
import OpenJoystickDriverKit

extension PhysicalOutputCommand {
  internal func plan(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let values = parsed.arguments
    guard values.count == 2 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(values[0], label: "VID")
    let productID = parseIdentifier(values[1], label: "PID")
    let device = requireDevice(
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

  internal func color(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 5 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    let components = zip(["red", "green", "blue"], arguments.dropFirst(2)).map { label, value in
      let parsed = parseInteger(value, label: label)
      guard (0...255).contains(parsed) else {
        fail(CLILocalized.text("cli.controller.colorRange", "Color components must be 0...255."))
      }
      return UInt8(parsed)
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    sendOutput(
      .setRGB(red: components[0], green: components[1], blue: components[2]),
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

  internal func brightness(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 3 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    let rawBrightness = parseInteger(arguments[2], label: "brightness")
    guard (0...255).contains(rawBrightness) else {
      fail(CLILocalized.text("cli.controller.brightnessRange", "Brightness must be 0...255."))
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    sendOutput(
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
