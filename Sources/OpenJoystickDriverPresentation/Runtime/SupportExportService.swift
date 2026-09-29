import Foundation
import OpenJoystickDriverKit

/// Assembles and writes support exports off the main actor.
///
/// The work reads logs, probes the service, and writes files, so each method runs it through
/// `BlockingWork` instead of on the `@MainActor` state that awaits it.
nonisolated struct SupportExportService: Sendable {
  func writeReport(
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    to outputURL: URL
  ) async throws {
    try await BlockingWork.run(label: "com.openjoystickdriver.support.report") {
      let report = SupportReportService.make(
        status: status,
        virtualDiagnostics: virtualDiagnostics,
        inputMonitoring: PermissionManager.AccessState(
          status: status?.inputMonitoring ?? "unknown"
        ),
        applicationServiceHealth: ApplicationServiceManager.health(),
        applicationServiceInstalled: ApplicationServiceManager.isInstalled,
        applicationServiceConnected: status != nil,
        buildIdentity: ApplicationVersion.buildIdentity,
        appleGameControllerAudit: AppleGameControllerSupportAuditor.auditCurrentSystem()
      )
      try SupportReportService.write(report, to: outputURL)
    }
  }

  func writeLogs(to outputURL: URL) async throws {
    try await BlockingWork.run(label: "com.openjoystickdriver.support.logs") {
      let snapshots = try ApplicationServiceLogStream.allCases.map {
        try ApplicationServiceLogService.tail(stream: $0)
      }
      let text = snapshots.map { snapshot in
        var section = "== \(snapshot.stream.rawValue) ==\n"
        if snapshot.exists {
          section += snapshot.lines.joined(separator: "\n")
          if !snapshot.lines.isEmpty { section += "\n" }
          if snapshot.truncated { section += "[tail truncated]\n" }
        } else {
          section += "[no log available]\n"
        }
        return section
      }.joined(separator: "\n")
      try Data(text.utf8).write(to: outputURL, options: .atomic)
    }
  }
}
