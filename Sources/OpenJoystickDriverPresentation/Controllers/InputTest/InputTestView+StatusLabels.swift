#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestView {

    var statusLabel: String {
      switch model.sessionState {
      case .idle: return OJDLocalized.string("inputTest.idle", fallback: "Ready")
      case .starting: return OJDLocalized.string("inputTest.starting", fallback: "Starting...")
      case .live: return OJDLocalized.string("inputTest.live", fallback: "Input active")
      case .stale: return OJDLocalized.string("inputTest.stale", fallback: "Input interrupted")
      case .disconnected:
        return OJDLocalized.string("inputTest.disconnected", fallback: "Controller disconnected")
      case .permissionRequired:
        return OJDLocalized.string(
          "inputTest.permissionRequired",
          fallback: "Input Monitoring permission required"
        )
      case .unavailable:
        return OJDLocalized.string("inputTest.unavailable", fallback: "Input unavailable")
      case .error: return OJDLocalized.string("common.failed", fallback: "Failed")
      }
    }

    var statusSemanticState: SemanticState {
      switch model.sessionState {
      case .live: return .active
      case .starting: return .loading
      case .stale, .permissionRequired: return .attention
      case .idle: return .inactive
      case .disconnected: return .disconnected
      case .unavailable: return .unknown
      case .error: return .failure
      }
    }

    func motorLabel(_ motor: PhysicalRumbleMotor) -> String {
      switch motor {
      case .leftMain: return OJDLocalized.string("inputTest.leftMain", fallback: "Left main")
      case .rightMain: return OJDLocalized.string("inputTest.rightMain", fallback: "Right main")
      case .leftTrigger:
        return OJDLocalized.string("inputTest.leftTrigger", fallback: "Left trigger")
      case .rightTrigger:
        return OJDLocalized.string("inputTest.rightTrigger", fallback: "Right trigger")
      case .leftHaptic: return OJDLocalized.string("inputTest.leftHaptic", fallback: "Left haptic")
      case .rightHaptic:
        return OJDLocalized.string("inputTest.rightHaptic", fallback: "Right haptic")
      }
    }

    func reported(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported", fallback: "Not reported") : trimmed
    }

    func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> String {
      guard device.vendorID != 0 || device.productID != 0 else {
        return OJDLocalized.string("controllers.notReported", fallback: "Not reported")
      }
      return String(format: "%04X:%04X", device.vendorID, device.productID)
    }
  }

#endif
