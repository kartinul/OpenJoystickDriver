import Foundation

@testable import OpenJoystickDriverKit

struct ContinuitySnapshotReportFormat: VirtualGamepadReportFormat {
  let descriptor: [UInt8] = []
  let inputReportPayloadSize = 19
  let inputReportID: UInt8? = nil

  func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var report = [
      UInt8(truncatingIfNeeded: state.buttons), UInt8(truncatingIfNeeded: state.buttons >> 8),
      UInt8(truncatingIfNeeded: state.buttons >> 16),
      UInt8(truncatingIfNeeded: state.buttons >> 24),
    ]
    for value in [
      state.leftStickX, state.leftStickY, state.rightStickX, state.rightStickY, state.leftTrigger,
      state.rightTrigger,
    ] {
      report.append(UInt8(truncatingIfNeeded: value))
      report.append(UInt8(truncatingIfNeeded: value >> 8))
    }
    report.append(state.leftTriggerPressed ? 1 : 0)
    report.append(state.rightTriggerPressed ? 1 : 0)
    report.append(state.hat.rawValue)
    return report
  }
}
