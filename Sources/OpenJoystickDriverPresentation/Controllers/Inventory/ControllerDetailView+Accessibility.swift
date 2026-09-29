#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    var accessibilityValue: String {
      let details = OJDLocalized.formatted(
        "controllers.accessibilityDetails",
        fallback: "%@. %@. Protocol: %@. Parser: %@. Serial number: %@. "
          + "USB VID/PID: %@. Input endpoint: %@. Output endpoint: %@.",
        reportedValue(device.connection),
        profileAccessibilityValue,
        device.protocolBinding.displayLabel,
        reportedValue(device.protocolBinding.rawValue),
        serialNumberLabel,
        usbIdentifier,
        endpointLabel(device.inputEndpoint),
        endpointLabel(device.outputEndpoint)
      )
      let battery = OJDLocalized.formatted(
        "controllers.batteryAccessibilityDetails",
        fallback: "Battery: %@. Charging state: %@. Cable state: %@.",
        batteryPercentageLabel,
        chargingStateLabel,
        cableStateLabel
      )
      return "\(details) \(battery)"
    }

    private var profileAccessibilityValue: String {
      switch activeProfile {
      case .loading:
        return OJDLocalized.string(
          "controllers.profileCheckingSentence",
          fallback: "Active profile is being checked."
        )
      case .noProfile:
        return OJDLocalized.string(
          "controllers.noActiveProfileSentence",
          fallback: "No active profile."
        )
      case .profile(let name):
        return OJDLocalized.formatted(
          "controllers.activeProfileSentence",
          fallback: "Active profile: %@.",
          name
        )
      case .unavailable(let message):
        return OJDLocalized.formatted(
          "controllers.profileUnavailableSentence",
          fallback: "Active profile unavailable: %@",
          message
        )
      case .error(let message):
        return OJDLocalized.formatted(
          "controllers.profileErrorSentence",
          fallback: "Active profile error: %@",
          message
        )
      }
    }
  }

#endif
