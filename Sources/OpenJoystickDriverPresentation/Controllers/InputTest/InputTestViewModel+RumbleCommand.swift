#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  extension InputTestViewModel {

    func rumbleCommand() -> (left: UInt8, right: UInt8, leftTrigger: UInt8, rightTrigger: UInt8) {
      var left: UInt8 = 0
      var right: UInt8 = 0
      var leftTrigger: UInt8 = 0
      var rightTrigger: UInt8 = 0
      let binary = Set(capabilities.binaryRumbleMotors)
      for motor in capabilities.rumbleMotors {
        let raw = rumbleIntensities[motor] ?? 0
        let value: UInt8 = binary.contains(motor) ? (raw > 0 ? 255 : 0) : Self.byte(raw)
        switch motor {
        case .leftMain, .leftHaptic: left = max(left, value)
        case .rightMain, .rightHaptic: right = max(right, value)
        case .leftTrigger: leftTrigger = value
        case .rightTrigger: rightTrigger = value
        }
      }
      return (left, right, leftTrigger, rightTrigger)
    }

    static func byte(_ value: Double) -> UInt8 {
      UInt8(clamping: Int(max(0, min(255, value)).rounded()))
    }
  }

#endif
