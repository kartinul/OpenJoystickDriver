import Foundation

public enum ControllerSessionState: String, Codable, Equatable, Sendable {
  case active
  case suspended
}

public enum ControllerSessionMutationFailure: String, Codable, Equatable, Sendable {
  case notFound = "not-found"
  case alreadySuspended = "already-suspended"
  case alreadyActive = "already-active"
}

public struct ControllerSuspendResult: Codable, Equatable, Sendable {
  public let state: ControllerSessionState
  public let failure: ControllerSessionMutationFailure?

  public init(state: ControllerSessionState, failure: ControllerSessionMutationFailure? = nil) {
    self.state = state
    self.failure = failure
  }

  public var succeeded: Bool { state == .suspended && failure == nil }

}

public struct ControllerResumeResult: Codable, Equatable, Sendable {
  public let state: ControllerSessionState
  public let failure: ControllerSessionMutationFailure?

  public init(state: ControllerSessionState, failure: ControllerSessionMutationFailure? = nil) {
    self.state = state
    self.failure = failure
  }

  public var succeeded: Bool { state == .active && failure == nil }
}

public enum WirelessControllerDisconnectFailure: String, Codable, Equatable, Sendable {
  case notFound = "not-found"
  case notBluetooth = "not-bluetooth"
  case missingAddress = "missing-address"
  case disconnectFailed = "disconnect-failed"
  case timedOut = "timed-out"
}

public enum WirelessControllerDisconnectStage: String, Codable, Equatable, Sendable {
  case releaseHIDClaim = "release-hid-claim"
  case closeBluetoothConnection = "close-bluetooth-connection"
  case confirmBluetoothDisconnection = "confirm-bluetooth-disconnection"
  case restoreHIDClaim = "restore-hid-claim"
  case restoreControllerSession = "restore-controller-session"
}

public struct WirelessControllerDisconnectResult: Codable, Equatable, Sendable {
  public let state: ControllerSessionState
  public let failure: WirelessControllerDisconnectFailure?
  public let failedStage: WirelessControllerDisconnectStage?
  public let systemCode: Int32?
  public let detail: String?
  public let recovery: String?

  public init(
    state: ControllerSessionState,
    failure: WirelessControllerDisconnectFailure? = nil,
    failedStage: WirelessControllerDisconnectStage? = nil,
    systemCode: Int32? = nil,
    detail: String? = nil,
    recovery: String? = nil
  ) {
    self.state = state
    self.failure = failure
    self.failedStage = failedStage
    self.systemCode = systemCode
    self.detail = detail
    self.recovery = recovery
  }

  public var succeeded: Bool { failure == nil }
}
