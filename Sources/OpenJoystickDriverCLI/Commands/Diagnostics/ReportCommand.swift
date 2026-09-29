import Foundation
import OpenJoystickDriverKit

struct ReportCommand {
  func run(arguments: [String]) async throws {
    var arguments = arguments
    if arguments.first == "create" {
      arguments.removeFirst()
    } else if let first = arguments.first, ["--help", "-h", "help"].contains(first) {
      printHelp()
      return
    } else if let first = arguments.first {
      CLIOutput.error(
        CLILocalized.format("cli.report.unknown_command", "Unknown report command: %@", first)
      )
      printHelp()
      throw CLIExit.failure
    }

    let outputURL = try parseOutputURL(arguments: arguments)
    let client = ApplicationServiceClient()
    await client.connect()

    let status = await withTimeout(seconds: 1.0) { try await client.getStatus() }
    let virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload? =
      status == nil
      ? nil : await withTimeout(seconds: 1.0) { try await client.getVirtualDeviceDiagnostics() }
    client.disconnect()

    let permissions = PermissionManager.AccessState(status: status?.inputMonitoring ?? "unknown")
    let health = ApplicationServiceManager.health()
    let report = SupportReportService.make(
      status: status,
      virtualDiagnostics: virtualDiagnostics,
      inputMonitoring: permissions,
      applicationServiceHealth: health,
      applicationServiceInstalled: ApplicationServiceManager.isInstalled,
      applicationServiceConnected: status != nil,
      buildIdentity: ApplicationVersion.buildIdentity,
      appleGameControllerAudit: AppleGameControllerSupportAuditor.auditCurrentSystem()
    )

    do {
      try SupportReportService.write(report, to: outputURL)
      print(
        CLILocalized.format("cli.report.written", "Support report written to %@", outputURL.path)
      )
      print(
        CLILocalized.text(
          "cli.report.review",
          "Review it before sharing; device product names are included."
        )
      )
    } catch {
      CLIOutput.error(error.localizedDescription)
      throw CLIExit.failure
    }
  }

  private func parseOutputURL(arguments: [String]) throws -> URL {
    if arguments.isEmpty {
      return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        SupportReportService.defaultFilename()
      )
    }
    guard arguments.count == 2, arguments[0] == "--output" else {
      printHelp()
      throw CLIExit.failure
    }
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return URL(fileURLWithPath: arguments[1], relativeTo: currentDirectory).standardizedFileURL
  }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.report.help",
        """
        Usage: OpenJoystickDriver --headless diagnose report [--output <path>]

        Creates a JSON support report for controller issues. Review it before sharing because \
        device product names are included.
        """
      ) + "\n\n"
        + CLILocalized.text(
          "cli.report.help_exclusions",
          "The report excludes raw serial values, filesystem paths, packet payloads, "
            + "HID location IDs, and free-form DriverKit discovery text."
        )
    )
  }
}
