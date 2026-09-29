import Foundation
import OpenJoystickDriverKit

extension InputCommand {

  /// Returns nil when help was requested and printed.
  func parse(_ arguments: [String]) throws -> Options? {
    guard let command = arguments.first else {
      printHelp()
      throw CLIExit.failure
    }
    if ["--help", "-h", "help"].contains(command) {
      printHelp()
      return nil
    }

    let action: Action
    switch command {
    case "state": action = .state
    case "packets": action = .packets
    case "trace": action = .trace
    case "watch": action = .watch
    default:
      CLIOutput.error(
        CLILocalized.format(
          "cli.controller.unknownCommand",
          "Unknown controller command: %@",
          command
        )
      )
      printHelp()
      throw CLIExit.failure
    }

    var options = Options(action: action)
    var identifiers: [UInt16] = []
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--json" where action == .state || action == .packets:
        options.json = true
        index += 1
      case "--json-lines" where action == .watch || action == .trace:
        options.jsonLines = true
        index += 1
      case "--limit" where action == .packets:
        options.limit = try parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 1...200
        )
      case "--seconds" where action == .watch || action == .trace:
        options.seconds = try parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 1...3_600
        )
      case "--interval-ms" where action == .watch || action == .trace:
        options.intervalMilliseconds = try parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 8...1_000
        )
      case "--device":
        guard options.runtimeIdentifier == nil, index + 1 < arguments.count else {
          CLIOutput.error(
            CLILocalized.text(
              "cli.controller.deviceRequired",
              "--device requires one unique identifier."
            )
          )
          throw CLIExit.failure
        }
        let identifier = arguments[index + 1]
        guard !identifier.isEmpty, !identifier.hasPrefix("--") else {
          CLIOutput.error(
            CLILocalized.text(
              "cli.controller.deviceRequired",
              "--device requires one unique identifier."
            )
          )
          throw CLIExit.failure
        }
        options.runtimeIdentifier = identifier
        index += 2
      default:
        guard !argument.hasPrefix("--"), let value = parseIdentifier(argument) else {
          CLIOutput.error(
            CLILocalized.format(
              "cli.controller.invalidOption",
              "Invalid controller option or identifier: %@",
              argument
            )
          )
          printHelp()
          throw CLIExit.failure
        }
        identifiers.append(value)
        index += 1
      }
    }

    guard identifiers.isEmpty || identifiers.count == 2 else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.controller.vidPidOrSingle",
          "Pass both VID and PID, or omit both when one controller is connected."
        )
      )
      throw CLIExit.failure
    }
    if identifiers.count == 2 {
      options.vendorID = identifiers[0]
      options.productID = identifiers[1]
    }
    return options
  }

  private func parseIntegerOption(
    _ arguments: [String],
    index: inout Int,
    option: String,
    range: ClosedRange<Int>
  ) throws -> Int {
    guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), range.contains(value)
    else {
      CLIOutput.error(
        CLILocalized.format(
          "cli.controller.optionRange",
          "%@ must be %d...%d.",
          option,
          range.lowerBound,
          range.upperBound
        )
      )
      throw CLIExit.failure
    }
    index += 2
    return value
  }

  private func parseIdentifier(_ raw: String) -> UInt16? {
    if raw.lowercased().hasPrefix("0x") { return UInt16(raw.dropFirst(2), radix: 16) }
    return UInt16(raw, radix: 10)
  }

  func hex(_ value: UInt16) -> String { String(format: "0x%04X", value) }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.controller.input.help",
        """
        Usage: OpenJoystickDriver --headless controller <state|packets|trace|watch> [options]

        Commands:
          state    Print the latest normalized buttons, sticks, and triggers
          packets  Print recent raw controller packets
          trace    Capture raw controller packets for a set duration
          watch    Print normalized state changes for a bounded duration

        VID and PID accept decimal or 0x-prefixed hexadecimal. Omit both when
        exactly one controller is connected. Use --device with the opaque ID
        reported by controller output list when identical models are connected.

        Options:
          state   [--device <id>] [--json]
          packets [--device <id>] [--limit 1...200] [--json]
          trace   [--device <id>] [--seconds 1...3600]
                  [--interval-ms 8...1000] [--json-lines]
          watch   [--device <id>] [--seconds 1...3600]
                  [--interval-ms 8...1000] [--json-lines]
        """
      )
    )
  }
}
