import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

final class AccessProbe: CoreGraphicsPostEventAccessProbing, @unchecked Sendable {
  private let results: [Bool]
  private let requestResult: Bool
  private(set) var preflightCount = 0
  private(set) var requestCount = 0

  init(preflight: [Bool], requestResult: Bool) {
    results = preflight
    self.requestResult = requestResult
  }

  func preflight() -> Bool {
    defer { preflightCount += 1 }
    return results[min(preflightCount, results.count - 1)]
  }

  func request() -> Bool {
    requestCount += 1
    return requestResult
  }
}
