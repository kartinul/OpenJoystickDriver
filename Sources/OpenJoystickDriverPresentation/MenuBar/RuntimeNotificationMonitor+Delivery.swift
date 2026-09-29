#if canImport(AppKit)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UserNotifications

  extension RuntimeNotificationMonitor {

    func observe(_ snapshot: RuntimeNotificationSnapshot) {
      guard let previousSnapshot else {
        self.previousSnapshot = snapshot
        return
      }
      self.previousSnapshot = snapshot
      for event in RuntimeNotificationDiff.events(from: previousSnapshot, to: snapshot) {
        deliver(event)
      }
    }

    func deliver(_ event: RuntimeNotificationEvent) {
      switch event {
      case .controllerConnected(let name):
        guard preferenceIsEnabled(ApplicationPreferenceKeys.controllerNotifications) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerConnected",
            fallback: "Controller connected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerConnectedBody",
            fallback: "%@ is ready to use.",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .controllerDisconnected(let name):
        guard
          preferenceIsEnabled(
            ApplicationPreferenceKeys.controllerDisconnectedNotifications,
            fallbackKey: ApplicationPreferenceKeys.controllerNotifications
          )
        else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerDisconnected",
            fallback: "Controller disconnected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerDisconnectedBody",
            fallback: "%@ is no longer connected.",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .activeProfileChanged(let previousName, let currentName):
        let preferenceKey =
          currentName == nil
          ? ApplicationPreferenceKeys.profileDeactivatedNotifications
          : ApplicationPreferenceKeys.profileNotifications
        let fallbackKey = currentName == nil ? ApplicationPreferenceKeys.profileNotifications : nil
        guard preferenceIsEnabled(preferenceKey, fallbackKey: fallbackKey) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.profileChanged",
            fallback: "Active profile changed"
          ),
          body: profileChangeBody(from: previousName, to: currentName),
          sound: notificationSoundIsEnabled
        )
      case .controllerNeedsAttention(let name):
        guard preferenceIsEnabled(ApplicationPreferenceKeys.controllerNotifications) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerNeedsAttention",
            fallback: "Controller needs attention"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerNeedsAttentionBody",
            fallback: "%@ input stopped updating. Release its controls or disconnect it.",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      }
    }

    private var notificationSoundIsEnabled: Bool {
      defaults.object(forKey: ApplicationPreferenceKeys.notificationSounds) as? Bool ?? true
    }

    private func preferenceIsEnabled(_ key: String, fallbackKey: String? = nil) -> Bool {
      if let value = defaults.object(forKey: key) as? Bool { return value }
      return fallbackKey.map { defaults.bool(forKey: $0) } ?? false
    }

    private func profileChangeBody(from previousName: String?, to currentName: String?) -> String {
      switch (previousName, currentName) {
      case (.some(let previous), .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileSwitchedBody",
          fallback: "%@ -> %@",
          previous,
          current
        )
      case (.none, .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileActivatedBody",
          fallback: "%@ is now active.",
          current
        )
      case (.some(let previous), .none):
        return OJDLocalized.formatted(
          "notifications.profileDeactivatedBody",
          fallback: "%@ is no longer active.",
          previous
        )
      case (.none, .none):
        return OJDLocalized.string("status.noActiveProfile", fallback: "No active profile")
      }
    }
  }

#endif
