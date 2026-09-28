import Foundation
import IOKit
import IOKit.hid

struct UserSpaceDeviceCreationRetryPolicy {
  static let defaultDelayNanoseconds: UInt64 = 5_000_000_000

  let delayNanoseconds: UInt64
  private(set) var nextAttemptNanoseconds: UInt64 = 0

  init(delayNanoseconds: UInt64 = Self.defaultDelayNanoseconds) {
    self.delayNanoseconds = delayNanoseconds
  }

  func permitsAttempt(at now: UInt64) -> Bool { now >= nextAttemptNanoseconds }

  mutating func recordFailure(at now: UInt64) {
    let (nextAttempt, overflow) = now.addingReportingOverflow(delayNanoseconds)
    nextAttemptNanoseconds = overflow ? UInt64.max : nextAttempt
  }
}
