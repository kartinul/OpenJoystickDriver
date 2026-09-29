import Foundation

@testable import OpenJoystickDriverKit

actor BarrierCompletionProbe {
  private(set) var isFinished = false

  func finish() { isFinished = true }
}
