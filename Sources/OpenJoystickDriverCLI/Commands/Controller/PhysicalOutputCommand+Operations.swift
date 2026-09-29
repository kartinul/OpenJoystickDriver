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

  func run(arguments: [String]) async throws {
    let subcommand = arguments.first ?? "list"
    switch subcommand {
    case "list": try await list(arguments: Array(arguments.dropFirst()))
    case "rumble": try await rumble(arguments: Array(arguments.dropFirst()))
    case "player": try await player(arguments: Array(arguments.dropFirst()))
    case "brightness": try await brightness(arguments: Array(arguments.dropFirst()))
    case "color": try await color(arguments: Array(arguments.dropFirst()))
    case "plan": try await plan(arguments: Array(arguments.dropFirst()))
    case "--help", "-h", "help": printHelp()
    default:
      try fail(
        CLILocalized.format(
          "cli.controller.unknownOutputCommand",
          "Unknown controller output command: %@",
          subcommand
        )
      )
    }
  }

  internal func list(arguments: [String]) async throws {
    guard arguments.allSatisfy({ $0 == "--json" }) && arguments.count <= 1 else {
      printHelp()
      throw CLIExit.failure
    }
    let devices = try await connectedDevices()
    if arguments.contains("--json") {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(devices.map(ListedDevice.init))
        print(String(data: data, encoding: .utf8) ?? "[]")
      } catch {
        try fail(
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

  internal func rumble(arguments: [String]) async throws {
    let parsed = try parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count >= 2 else {
      printHelp()
      throw CLIExit.failure
    }
    let vendorID = try parseIdentifier(arguments[0], label: "VID")
    let productID = try parseIdentifier(arguments[1], label: "PID")
    var left = UInt8(180)
    var right = UInt8(180)
    var lt = UInt8(0)
    var rt = UInt8(0)
    var durationMs = 450
    var index = 2
    while index < arguments.count {
      guard index + 1 < arguments.count else {
        try fail(
          CLILocalized.format(
            "cli.controller.missingOptionValue",
            "Missing value for %@",
            arguments[index]
          )
        )
      }
      let option = arguments[index]
      let value = try parseInteger(arguments[index + 1], label: option)
      switch option {
      case "--left": left = try parseIntensity(value, label: option)
      case "--right": right = try parseIntensity(value, label: option)
      case "--lt": lt = try parseIntensity(value, label: option)
      case "--rt": rt = try parseIntensity(value, label: option)
      case "--duration-ms":
        guard (0...5_000).contains(value) else {
          try fail(
            CLILocalized.text("cli.controller.durationRange", "--duration-ms must be 0...5000")
          )
        }
        durationMs = value
      default:
        try fail(
          CLILocalized.format(
            "cli.controller.unknownRumbleOption",
            "Unknown rumble option: %@",
            option
          )
        )
      }
      index += 2
    }

    let device = try await requireDevice(
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
    let result = try await sendOutput(
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
      try fail(failure)
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

  internal func player(arguments: [String]) async throws {
    let parsed = try parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 3 else {
      printHelp()
      throw CLIExit.failure
    }
    let vendorID = try parseIdentifier(arguments[0], label: "VID")
    let productID = try parseIdentifier(arguments[1], label: "PID")
    let indicator: PhysicalPlayerIndicator

    if arguments[2] == "off" {
      indicator = .off
    } else {
      let rawValue = try parseInteger(arguments[2], label: "player")
      guard let parsed = PhysicalPlayerIndicator(rawValue: rawValue), parsed != .off else {
        try fail(
          CLILocalized.text("cli.controller.invalidPlayer", "Player must be off, 1, 2, 3, or 4.")
        )
      }
      indicator = parsed
    }

    let device = try await requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    try await sendOutput(
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

  internal func connectedDevices() async throws -> [ApplicationServiceDeviceDescription] {
    let client = ApplicationServiceClient()
    await client.connect()
    defer { client.disconnect() }
    guard
      let status = await withTimeout(
        seconds: serviceCallTimeoutSeconds,
        { try await client.getStatus() }
      )
    else {
      try fail(
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
  ) async throws -> ApplicationServiceDeviceDescription {
    let devices = try await connectedDevices()
    do {
      return try ConnectedControllerSelection.resolve(
        devices: devices,
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: runtimeIdentifier
      )
    } catch { try fail(error.localizedDescription) }
  }
}
