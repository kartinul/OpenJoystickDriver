import Foundation
import IOKit

public enum WirelessControllerDisconnectOutcome: Sendable, Equatable {
  case disconnected
  case failed(IOReturn)
  case stillConnected
  case timedOut
}

public protocol WirelessControllerDisconnecting: Sendable {
  func disconnect(
    address: String,
    timeoutNanoseconds: UInt64
  ) async -> WirelessControllerDisconnectOutcome
}
