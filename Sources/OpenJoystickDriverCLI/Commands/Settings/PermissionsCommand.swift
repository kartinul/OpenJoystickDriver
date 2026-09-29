import AppKit
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

func printPermissionSnapshot(_ permissions: StatusPermissions) {
  permissionSnapshotLines(permissions).forEach { print($0) }
}

func printPermissionSnapshot(_ snapshot: PermissionManager.Snapshot) {
  printPermissionSnapshot(StatusPermissions(snapshot))
}

func permissionSnapshotLines(_ permissions: StatusPermissions) -> [String] {
  RuntimeStatusText.permissionLines(permissions)
}

struct PermissionsCommand {
  let serviceCallTimeoutSeconds: Double

  func run(arguments: [String]) async throws {
    switch arguments.first ?? "status" {
    case "status": try await printStatus()
    case "request": try await requestAccess(arguments: Array(arguments.dropFirst()))
    case "open": try openSettings(arguments: Array(arguments.dropFirst()))
    case "explain": printPermissionInventory()
    case "--help", "-h", "help": printHelp()
    case let command:
      CLIOutput.error(
        CLILocalized.format(
          "cli.permissions.unknown_command",
          "Unknown permissions command: %@",
          command
        )
      )
      printHelp()
      throw CLIExit.failure
    }
  }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.permissions.help",
        """
        Usage: OpenJoystickDriver --headless permissions <command>

        Commands:
          status                     Show the main app permission states
          request                    Request required permissions for the main app
          open [input|output]
                                     Open Input Monitoring or Accessibility
          explain                    Explain every permission OJD may request
        """
      )
    )
  }

  private func connectedClient() async throws -> ApplicationServiceClient {
    let client = ApplicationServiceClient()
    await client.connect()
    guard client.isConnected else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.permissions.connect_error",
          "Could not connect to the installed main app. Launch it manually, then verify "
            + "Input Monitoring and Accessibility access."
        )
      )
      throw CLIExit.failure
    }
    return client
  }

  private func printStatus() async throws {
    let client = ApplicationServiceClient()
    await client.connect()
    defer { client.disconnect() }
    let result = await withTimeout(seconds: serviceCallTimeoutSeconds) {
      try await client.getStatus()
    }
    guard let payload = result else {
      printPermissionSnapshot(localPermissionSnapshot())
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.permissions.local_source",
          "State source: local system (main app did not return status)"
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.permissions.launch_recovery",
          "Recovery: launch the installed OpenJoystickDriver app"
        )
      )
      throw CLIExit.failure
    }

    let status = RuntimeStatusSnapshot(payload: payload)
    printPermissionSnapshot(status.permissions)
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic(
      CLILocalized.text("cli.permissions.app_source", "State source: running main app")
    )
    if !status.permissions.isReady {
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.permissions.request_recovery",
          "Recovery: run --headless permissions request"
        )
      )
    }
  }

  private func localPermissionSnapshot() -> PermissionManager.Snapshot {
    PermissionManager.Snapshot(
      inputMonitoring: PermissionManager.currentInputMonitoringAccessState(),
      accessibility: PermissionManager.currentAccessibilityAccessState()
    )
  }

  private func printPermissionInventory() {
    print(CLILocalized.text("cli.permissions.inventory", "Permission inventory:"))
    for requirement in OJDPermissionRequirement.inventory {
      let behavior =
        requirement.requested
        ? CLILocalized.text("cli.permissions.may_request", "may request")
        : CLILocalized.text("cli.permissions.never_requests", "never requests")
      print("  \(requirement.name) - \(requirement.owner) [\(behavior)]")
      print("    \(requirement.purpose)")
    }
  }

  private func requestAccess(arguments: [String]) async throws {
    guard arguments.isEmpty else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.permissions.request_usage",
          "Usage: OpenJoystickDriver --headless permissions request"
        )
      )
      throw CLIExit.failure
    }
    let client = try await connectedClient()
    defer { client.disconnect() }
    let result = await withTimeout(seconds: 10) { try await client.requestRequiredAccess() }
    guard let snapshot = result else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.permissions.no_status",
          "The main app did not return permission status. Launch it manually and retry."
        )
      )
      throw CLIExit.failure
    }
    printPermissionSnapshot(snapshot)
    guard snapshot.isReady else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.permissions.blocked",
          "Required access is blocked. Grant Input Monitoring and Accessibility in "
            + "System Settings > Privacy & Security, then retry."
        )
      )
      if snapshot.inputMonitoring != .granted {
        try openPermissionSettings(kind: "input")
      } else {
        try openPermissionSettings(kind: "output")
      }
      throw CLIExit(code: 2)
    }
  }

  private func openSettings(arguments: [String]) throws {
    guard arguments.count <= 1 else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.permissions.open_usage",
          "Usage: OpenJoystickDriver --headless permissions open [input|output]"
        )
      )
      throw CLIExit.failure
    }
    try openPermissionSettings(kind: arguments.first ?? "input")
  }

  private func openPermissionSettings(kind: String) throws {
    let pane: String
    switch kind {
    case "input": pane = "Privacy_ListenEvent"
    case "output": pane = "Privacy_Accessibility"
    default:
      CLIOutput.error(
        CLILocalized.format("cli.permissions.unknown_kind", "Unknown permission kind: %@", kind)
      )
      throw CLIExit.failure
    }
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    if let url, NSWorkspace.shared.open(url) { return }
    CLIOutput.warning(
      CLILocalized.text(
        "cli.permissions.open_failed",
        "Could not open the requested privacy pane; opening System Settings."
      )
    )
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
