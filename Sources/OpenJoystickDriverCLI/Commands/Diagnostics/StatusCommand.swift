import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct StatusCommand {
  let serviceCallTimeoutSeconds: Double

  func run(arguments: [String] = []) async throws {
    guard arguments.isEmpty || arguments == ["--json"] else {
      CLIOutput.error(CLILocalized.text("cli.status.json_only", "status accepts only --json."))
      throw CLIExit(code: CLIParseError.exitCode)
    }
    let json = arguments.contains("--json")
    if !json { printHeader() }
    let client = ApplicationServiceClient()
    await client.connect(timeoutSeconds: serviceCallTimeoutSeconds)
    let servicePayload = await withTimeout(seconds: serviceCallTimeoutSeconds) {
      try await client.getStatus()
    }

    if let payload = servicePayload {
      if json { try printJSON(payload) } else { printPayloadStatus(payload) }
    } else {
      client.disconnect()
      if json { try await printJSON(directPayload()) } else { await runDirectMode() }
    }
    if !json {
      print("")
      printUsageHint()
    }
  }

  private func printHeader() {
    print(CLILocalized.text("cli.status.heading", "OpenJoystickDriver Status"))
    let divider = String(repeating: "\u{2500}", count: 25)
    print(divider)
    print("")
  }

  private func printPayloadStatus(_ payload: ApplicationServiceStatusPayload) {
    RuntimeStatusText.payloadLines(RuntimeStatusSnapshot(payload: payload)).forEach { print($0) }
  }

  private func printUsageHint() {
    print(
      CLILocalized.text(
        "cli.status.usage_hint",
        "Use '--headless controller list' to enumerate controllers."
      )
    )
  }

  private func runDirectMode() async {
    RuntimeStatusText.directModeLines(await localPermissionStatus()).forEach { line in
      if line.hasPrefix("  -> App recovery:") { CLIOutput.diagnostic(line) } else { print(line) }
    }
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.status.access_denied",
        "If access is denied, run --headless permissions request and approve "
          + "Input Monitoring and Accessibility in System Settings."
      )
    )
  }

  private func printJSON(_ payload: ApplicationServiceStatusPayload) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data: Data
    do { data = try encoder.encode(payload) } catch {
      CLIOutput.error(
        CLILocalized.format(
          "cli.status.json_error",
          "Could not encode status JSON: %@",
          error.localizedDescription
        )
      )
      throw CLIExit.failure
    }
    guard let text = String(bytes: data, encoding: .utf8) else {
      CLIOutput.error(
        CLILocalized.text("cli.status.json_utf8_error", "Could not encode status JSON as UTF-8.")
      )
      throw CLIExit.failure
    }
    print(text)
  }

  private func directPayload() async -> ApplicationServiceStatusPayload {
    let permissions = await localPermissionStatus()
    return ApplicationServiceStatusPayload(
      inputMonitoring: permissions.inputMonitoring.rawValue,
      accessibility: permissions.accessibility.rawValue,
      connectedDevices: []
    )
  }

  private func localPermissionStatus() async -> StatusPermissions {
    let snapshot =
      await withTimeout(seconds: serviceCallTimeoutSeconds) {
        PermissionManager.Snapshot(
          inputMonitoring: PermissionManager.currentInputMonitoringAccessState(),
          accessibility: PermissionManager.currentAccessibilityAccessState()
        )
      } ?? PermissionManager.Snapshot(inputMonitoring: .unknown, accessibility: .unknown)
    return StatusPermissions(snapshot)
  }
}
