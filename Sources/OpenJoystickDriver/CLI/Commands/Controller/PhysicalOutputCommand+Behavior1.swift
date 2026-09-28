import Foundation
import OpenJoystickDriverKit

extension PhysicalOutputCommand {
  internal struct ListedDevice: Codable {
    let id: String
    let name: String
    let vendorID: UInt16
    let productID: UInt16
    let protocolBinding: ProtocolBindingID
    let connection: String
    let physicalOutputCapabilities: PhysicalControllerOutputCapabilities

    init(_ device: ApplicationServiceDeviceDescription) {
      id = device.runtimeIdentifier
      name = device.name
      vendorID = device.vendorID
      productID = device.productID
      protocolBinding = device.protocolBinding
      connection = device.connection
      physicalOutputCapabilities = device.physicalOutputCapabilities
    }
  }

  func run(arguments: [String]) {
    let subcommand = arguments.first ?? "list"
    switch subcommand {
    case "list": list(arguments: Array(arguments.dropFirst()))
    case "rumble": rumble(arguments: Array(arguments.dropFirst()))
    case "player": player(arguments: Array(arguments.dropFirst()))
    case "brightness": brightness(arguments: Array(arguments.dropFirst()))
    case "color": color(arguments: Array(arguments.dropFirst()))
    case "plan": plan(arguments: Array(arguments.dropFirst()))
    case "--help", "-h", "help": printHelp()
    default:
      fail(
        CLILocalized.format(
          "cli.controller.unknownOutputCommand",
          "Unknown controller output command: %@",
          subcommand
        )
      )
    }
  }

  internal func list(arguments: [String]) {
    guard arguments.allSatisfy({ $0 == "--json" }) && arguments.count <= 1 else {
      printHelp()
      exit(1)
    }
    let devices = connectedDevices()
    if arguments.contains("--json") {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(devices.map(ListedDevice.init))
        print(String(data: data, encoding: .utf8) ?? "[]")
      } catch {
        fail(
          CLILocalized.format(
            "cli.controller.outputEncodeFailed",
            "Could not encode physical output capabilities: %@",
            error.localizedDescription
          )
        )
      }
      return
    }

    if devices.isEmpty {
      print(
        CLILocalized.text(
          "cli.controller.noPhysicalOutputDevices",
          "Physical output devices: (none connected)"
        )
      )
      return
    }
    print(
      CLILocalized.format(
        "cli.controller.physicalOutputDevices",
        "Physical output devices (%d):",
        devices.count
      )
    )
    for device in devices {
      let capabilities = device.physicalOutputCapabilities
      print("  \(device.name) (\(hex(device.vendorID)):\(hex(device.productID)))")
      print("    device   : \(device.runtimeIdentifier)")
      print("    motors   : \(names(capabilities.rumbleMotors.map(\.rawValue)))")
      print("    lighting : \(names(capabilities.lightingFeatures.map(\.rawValue)))")
      print("    binary   : \(names(capabilities.binaryRumbleMotors.map(\.rawValue)))")
    }
  }

  internal func rumble(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count >= 2 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    var left = UInt8(180)
    var right = UInt8(180)
    var lt = UInt8(0)
    var rt = UInt8(0)
    var durationMs = 450
    var index = 2
    while index < arguments.count {
      guard index + 1 < arguments.count else {
        fail(
          CLILocalized.format(
            "cli.controller.missingOptionValue",
            "Missing value for %@",
            arguments[index]
          )
        )
      }
      let option = arguments[index]
      let value = parseInteger(arguments[index + 1], label: option)
      switch option {
      case "--left": left = parseIntensity(value, label: option)
      case "--right": right = parseIntensity(value, label: option)
      case "--lt": lt = parseIntensity(value, label: option)
      case "--rt": rt = parseIntensity(value, label: option)
      case "--duration-ms":
        guard (0...5_000).contains(value) else {
          fail(CLILocalized.text("cli.controller.durationRange", "--duration-ms must be 0...5000"))
        }
        durationMs = value
      default:
        fail(
          CLILocalized.format(
            "cli.controller.unknownRumbleOption",
            "Unknown rumble option: %@",
            option
          )
        )
      }
      index += 2
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    // All-zero is a stop; otherwise the daemon ends the rumble after the duration.
    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(byte: left),
      rightMain: UnipolarValue(byte: right),
      leftTrigger: UnipolarValue(byte: lt),
      rightTrigger: UnipolarValue(byte: rt)
    ).mirroringMainOntoHaptics()
    let result = sendOutput(
      intensities == .off
        ? .stopRumble : .setRumble(intensities, duration: .milliseconds(durationMs)),
      to: device,
      unsupported: Message(
        key: "cli.controller.noRumble",
        english: "The selected controller has no physical rumble implementation."
      ),
      failed: Message(
        key: "cli.controller.rumbleFailed",
        english: "The application service could not send the physical rumble command."
      )
    )
    var messages = droppedTriggerMotorMessages(result)
    let requested = intensities.activeMotors
    // A request whose every channel was dropped drove nothing: it fails with the last message.
    if !requested.isEmpty, requested.allSatisfy(result.droppedRumbleChannels.contains) {
      let failure =
        messages.popLast()
        ?? CLILocalized.text(
          "cli.controller.noRumble",
          "The selected controller has no physical rumble implementation."
        )
      for message in messages { CLIOutput.warning(message) }
      fail(failure)
    }
    for message in messages { CLIOutput.warning(message) }
    print(
      CLILocalized.format(
        "cli.controller.rumbleSent",
        "Physical rumble command sent to %@:%@.",
        hex(vendorID),
        hex(productID)
      )
    )
  }

  internal func player(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 3 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    let indicator: PhysicalPlayerIndicator

    if arguments[2] == "off" {
      indicator = .off
    } else {
      let rawValue = parseInteger(arguments[2], label: "player")
      guard let parsed = PhysicalPlayerIndicator(rawValue: rawValue), parsed != .off else {
        fail(
          CLILocalized.text("cli.controller.invalidPlayer", "Player must be off, 1, 2, 3, or 4.")
        )
      }
      indicator = parsed
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    sendOutput(
      .setPlayerIndicator(indicator),
      to: device,
      unsupported: Message(
        key: "cli.controller.noPlayerIndicator",
        english: "The selected controller has no source-backed player-indicator implementation."
      ),
      failed: Message(
        key: "cli.controller.playerIndicatorFailed",
        english: "The application service could not set the physical player indicator."
      )
    )
    print(
      CLILocalized.format(
        "cli.controller.playerIndicatorSet",
        "Physical player indicator set on %@:%@.",
        hex(vendorID),
        hex(productID)
      )
    )
  }

  internal func connectedDevices() -> [ApplicationServiceDeviceDescription] {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    guard
      let status: ApplicationServiceStatusPayload = runSyncOptionalResult(
        timeout: applicationServiceCallTimeoutSeconds,
        { try? await client.getStatus() }
      )
    else {
      fail(
        CLILocalized.text(
          "cli.controller.serviceUnavailable",
          "The application service is unavailable."
        )
      )
    }
    return status.connectedDevices
  }

  internal func requireDevice(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) -> ApplicationServiceDeviceDescription {
    do {
      return try ConnectedControllerSelection.resolve(
        devices: connectedDevices(),
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: runtimeIdentifier
      )
    } catch { fail(error.localizedDescription) }
  }
}
