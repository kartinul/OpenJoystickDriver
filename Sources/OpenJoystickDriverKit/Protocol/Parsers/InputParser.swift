import Foundation

/// Receiver-backed controllers can report logical controller connect/disconnect
/// independently from the HID device that carries reports.
public enum ControllerInputConnectionState: Sendable, Equatable {
  case connected
  case disconnected
}

public enum ControllerInputHealthState: String, Codable, Sendable {
  case healthy
  case stale
  case waitingForNeutral
}

public enum ControllerInputHealthFailureReason: String, Codable, Sendable {
  case missingReports
  case freshnessNotAdvancing
}

public struct ControllerInputHealth: Codable, Sendable {
  public let state: ControllerInputHealthState
  public let reportFormat: String?
  public let lastReportAgeNanoseconds: UInt64?
  public let failureReason: ControllerInputHealthFailureReason?
  public let recoveryCount: Int

  public init(
    state: ControllerInputHealthState,
    reportFormat: String? = nil,
    lastReportAgeNanoseconds: UInt64? = nil,
    failureReason: ControllerInputHealthFailureReason? = nil,
    recoveryCount: Int = 0
  ) {
    self.state = state
    self.reportFormat = reportFormat
    self.lastReportAgeNanoseconds = lastReportAgeNanoseconds
    self.failureReason = failureReason
    self.recoveryCount = recoveryCount
  }
}
