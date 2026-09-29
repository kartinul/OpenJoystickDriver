import Foundation

@testable import OpenJoystickDriverKit

final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }

  func current() -> Int { lock.withLock { value } }
}
