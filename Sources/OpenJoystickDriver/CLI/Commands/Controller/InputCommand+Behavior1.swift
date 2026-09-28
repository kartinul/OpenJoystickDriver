import Foundation
import OpenJoystickDriverKit

extension InputCommand {

  enum Action {
    case state
    case packets
    case trace
    case watch
  }

  struct Options {
    var action: Action
    var vendorID: UInt16?
    var productID: UInt16?
    var runtimeIdentifier: String?
    var json = false
    var jsonLines = false
    var limit = 50
    var seconds = 10
    var intervalMilliseconds = 16
  }

  func execute(_ options: Options, service: ControllerInputDiagnosticService) async -> String? {
    do {
      let device = try await resolveDevice(options, service: service)
      switch options.action {
      case .state: try await printState(device, json: options.json, service: service)
      case .packets:
        try await printPackets(device, limit: options.limit, json: options.json, service: service)
      case .trace:
        try await tracePackets(
          device,
          seconds: options.seconds,
          intervalMilliseconds: options.intervalMilliseconds,
          jsonLines: options.jsonLines,
          service: service
        )
      case .watch:
        try await watch(
          device,
          seconds: options.seconds,
          intervalMilliseconds: options.intervalMilliseconds,
          jsonLines: options.jsonLines,
          service: service
        )
      }
      return nil
    } catch { return error.localizedDescription }
  }

  private func resolveDevice(
    _ options: Options,
    service: ControllerInputDiagnosticService
  ) async throws -> ApplicationServiceDeviceDescription {
    let devices = try await service.connectedDevices()
    return try ConnectedControllerSelection.resolve(
      devices: devices,
      vendorID: options.vendorID,
      productID: options.productID,
      runtimeIdentifier: options.runtimeIdentifier
    )
  }

  private func printState(
    _ device: ApplicationServiceDeviceDescription,
    json: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    guard
      let state = try await service.controllerState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
    else {
      throw InputCommandFailure(
        CLILocalized.format(
          "cli.controller.noInputFrom",
          "No input received from %@:%@.",
          hex(device.vendorID),
          hex(device.productID)
        )
      )
    }

    if json {
      try printJSON(state, pretty: true)
      return
    }
    print(
      CLILocalized.format(
        "cli.controller.state",
        "Controller state %@:%@",
        hex(device.vendorID),
        hex(device.productID)
      )
    )
    print("  \(formatted(state))")
  }

  private func printPackets(
    _ device: ApplicationServiceDeviceDescription,
    limit: Int,
    json: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let entries = try await service.packetLog(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )
    let selected = Array(entries.suffix(limit))
    warnAboutRawPackets()

    if json {
      try printJSON(selected, pretty: true)
      return
    }

    print(
      CLILocalized.format(
        "cli.controller.recentPackets",
        "Recent packets %@:%@ (%d/%d)",
        hex(device.vendorID),
        hex(device.productID),
        selected.count,
        entries.count
      )
    )
    if selected.isEmpty {
      print("  \(CLILocalized.text("cli.controller.noPackets", "(no packets)"))")
      return
    }
    for entry in selected {
      print(
        "  \(String(format: "%.3f", entry.timestamp)) "
          + "\(entry.direction) len=\(entry.length) \(entry.hex)"
      )
    }
  }

  func watch(
    _ device: ApplicationServiceDeviceDescription,
    seconds: Int,
    intervalMilliseconds: Int,
    jsonLines: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let deadline =
      DispatchTime.now().uptimeNanoseconds + UInt64(seconds) * Self.nanosecondsPerSecond
    let interval = UInt64(intervalMilliseconds) * Self.nanosecondsPerMillisecond
    var previous: ControllerState?
    var observedState = false

    if !jsonLines {
      print(
        CLILocalized.format(
          "cli.controller.readingInput",
          "Reading input from %@:%@ for %d seconds. Press controller buttons.",
          hex(device.vendorID),
          hex(device.productID),
          seconds
        )
      )
    }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let state = try await service.controllerState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
      if let state, state != previous {
        observedState = true
        if jsonLines { try printJSON(state, pretty: false) } else { print("  \(formatted(state))") }
        previous = state
      }
      try await Task.sleep(nanoseconds: interval)
    }

    if !observedState && !jsonLines {
      print(CLILocalized.text("cli.controller.noInput", "No input received."))
    }
  }

  private func tracePackets(
    _ device: ApplicationServiceDeviceDescription,
    seconds: Int,
    intervalMilliseconds: Int,
    jsonLines: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let initialEntries = try await service.packetLog(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )
    var cursor = PacketLogSnapshotCursor(snapshot: initialEntries)
    let deadline =
      DispatchTime.now().uptimeNanoseconds + UInt64(seconds) * Self.nanosecondsPerSecond
    let interval = UInt64(intervalMilliseconds) * Self.nanosecondsPerMillisecond
    var observedPacket = false

    warnAboutRawPackets()
    let traceStatus = CLILocalized.format(
      "cli.controller.capturingPackets",
      "Capturing packets from %@:%@ for %d seconds. Press controller buttons.",
      hex(device.vendorID),
      hex(device.productID),
      seconds
    )
    if jsonLines { CLIOutput.diagnostic(traceStatus) } else { print(traceStatus) }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let entries = try await service.packetLog(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
      for entry in cursor.consume(snapshot: entries) {
        observedPacket = true
        if jsonLines {
          try printJSON(entry, pretty: false)
        } else {
          print(
            "  \(String(format: "%.3f", entry.timestamp)) "
              + "\(entry.direction) len=\(entry.length) \(entry.hex)"
          )
        }
      }
      try await Task.sleep(nanoseconds: interval)
    }

    if !observedPacket {
      let message = CLILocalized.text("cli.controller.noPacketsReceived", "No packets received.")
      if jsonLines { CLIOutput.diagnostic(message) } else { print(message) }
    }
  }

  /// Pressed controls in `ControlID` order, the hat, and the raw canonical stick and trigger
  /// values; stick Y points up.
  private func formatted(_ state: ControllerState) -> String {
    let pressed = ControlID.allCases.filter(state.pressed.contains).map(\.rawValue)
    let buttons = pressed.isEmpty ? "none" : pressed.joined(separator: ",")
    return "buttons=[\(buttons)] hat=\(state.hat.rawValue)"
      + " LS=(\(state.leftStick.x.rawValue),\(state.leftStick.y.rawValue))"
      + " RS=(\(state.rightStick.x.rawValue),\(state.rightStick.y.rawValue))"
      + " LT=\(state.leftTrigger.rawValue) RT=\(state.rightTrigger.rawValue)"
  }

  private func printJSON<T: Encodable>(_ value: T, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data = try encoder.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
      throw InputCommandFailure(
        CLILocalized.text("cli.controller.jsonEncodeFailed", "Could not encode UTF-8 JSON output.")
      )
    }
    print(output)
  }

  private func warnAboutRawPackets() {
    CLIOutput.warning(
      CLILocalized.text(
        "cli.controller.packetWarning",
        "Packet contents vary by controller. Check them before sharing."
      )
    )
  }
}
