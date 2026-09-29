import Foundation

let applicationServiceDefaultReplyTimeoutSeconds: TimeInterval = 5
let applicationServiceSelfTestReplyGraceSeconds: TimeInterval = 5

public enum ApplicationServiceClientError: Error, LocalizedError, Sendable {
  case notConnected
  case timeout
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .notConnected: return "Not connected to main application."
    case .timeout: return "Main application did not respond before the deadline."
    case .invalidResponse: return "Main application returned an invalid response."
    }
  }
}

public final class ApplicationServiceClient: @unchecked Sendable {
  let stateLock = NSLock()
  let socketPath: String
  var connected = false

  public init() { socketPath = LocalServiceRPCTransport.defaultSocketPath }

  init(socketPath: String) { self.socketPath = socketPath }
}

extension ApplicationServiceClient {
  enum LaunchPolicy: Equatable, Sendable {
    case waitForLocalServer
    case spawnBundleExecutable
    case unavailable
  }

  static let concurrentHostLaunchGraceSeconds: TimeInterval = 0.5

  static func launchPolicy(
    commandLineArguments: [String],
    bundlePathExtension: String
  ) -> LaunchPolicy {
    guard bundlePathExtension == "app" else { return .unavailable }
    if commandLineArguments.dropFirst().isEmpty { return .waitForLocalServer }
    return .spawnBundleExecutable
  }
}
