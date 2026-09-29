import Foundation
import OpenJoystickDriverKit

extension PhysicalOutputCommand {

  internal func parseDeviceOption(
    _ arguments: [String]
  ) throws -> (arguments: [String], runtimeIdentifier: String?) {
    var values: [String] = []
    var runtimeIdentifier: String?
    var index = 0
    while index < arguments.count {
      if arguments[index] == "--device" {
        guard runtimeIdentifier == nil, index + 1 < arguments.count else {
          try fail(
            CLILocalized.text(
              "cli.controller.deviceRequiredList",
              "--device requires one unique identifier from controller output list."
            )
          )
        }
        let identifier = arguments[index + 1]
        guard !identifier.isEmpty, !identifier.hasPrefix("--") else {
          try fail(
            CLILocalized.text(
              "cli.controller.deviceRequiredList",
              "--device requires one unique identifier from controller output list."
            )
          )
        }
        runtimeIdentifier = identifier
        index += 2
      } else {
        values.append(arguments[index])
        index += 1
      }
    }
    return (values, runtimeIdentifier)
  }

  internal func parseIdentifier(_ value: String, label: String) throws -> UInt16 {
    let radix = value.lowercased().hasPrefix("0x") ? 16 : 10
    let digits = radix == 16 ? String(value.dropFirst(2)) : value
    guard let parsed = UInt16(digits, radix: radix) else {
      try fail(
        CLILocalized.format(
          "cli.controller.labelInvalid16",
          "%@ must be a decimal or 0x-prefixed 16-bit value.",
          label
        )
      )
    }
    return parsed
  }

  internal func parseInteger(_ value: String, label: String) throws -> Int {
    guard let parsed = Int(value) else {
      try fail(CLILocalized.format("cli.controller.labelInteger", "%@ must be an integer.", label))
    }
    return parsed
  }

  internal func parseIntensity(_ value: Int, label: String) throws -> UInt8 {
    guard (0...255).contains(value) else {
      try fail(CLILocalized.format("cli.controller.labelRange255", "%@ must be 0...255.", label))
    }
    return UInt8(value)
  }

  internal func names(_ values: [String]) -> String {
    values.isEmpty ? "none" : values.joined(separator: ",")
  }

  internal func hex(_ value: UInt16) -> String { String(format: "%04x", value) }

  internal func fail(_ message: String) throws -> Never {
    CLIOutput.error(message)
    throw CLIExit.failure
  }

  internal func printHelp() {
    print(
      CLILocalized.text(
        "cli.controller.output.help",
        """
        Usage: OpenJoystickDriver --headless controller output <command>

        Commands:
          list [--json]
          rumble <vid> <pid> [--device <id>] [--left 0...255] [--right 0...255]
                 [--lt 0...255] [--rt 0...255] [--duration-ms 0...5000]
          player <vid> <pid> off|1|2|3|4 [--device <id>]
          brightness <vid> <pid> 0...255 [--device <id>]
          color <vid> <pid> <red 0...255> <green 0...255> <blue 0...255> [--device <id>]
          plan <vid> <pid> [--device <id>]

        VID and PID accept decimal values or a 0x prefix. Output commands write to
        connected physical hardware and reject capabilities the active parser does
        not implement. When identical models are connected, pass the opaque device
        identifier printed by controller output list.
        """
      )
    )
  }
}
