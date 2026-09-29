import Foundation
import Testing

@testable import OpenJoystickDriverKit

enum ExpectedButtonOutput {
  case bit(Int)
  case leftTrigger
  case rightTrigger
}

struct UserSpaceOutputDispatcherLifecycleTests {}
