#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension ApplicationSettingsView {

    var updateStatusTitle: String {
      switch preferences.updateState {
      case .idle: return OJDLocalized.string("settings.updateIdle", fallback: "Check for updates")
      case .checking: return OJDLocalized.string("settings.updateChecking", fallback: "Checking...")
      case .upToDate: return OJDLocalized.string("settings.upToDate", fallback: "Up to date")
      case .available:
        return OJDLocalized.string("settings.updateAvailable", fallback: "Update available")
      case .failed:
        return OJDLocalized.string("settings.updateFailed", fallback: "Update check failed")
      }
    }

    var updateStatusDetail: String {
      switch preferences.updateState {
      case .idle:
        return OJDLocalized.formatted(
          "settings.currentVersion",
          fallback: "Current version: %@",
          ApplicationVersion.current
        )
      case .checking:
        return OJDLocalized.string("settings.contactingGitHub", fallback: "Contacting GitHub...")
      case .upToDate(let tag): return tag
      case .available(let info): return info.tagName
      case .failed(let failure): return failure.message
      }
    }
  }

#endif
