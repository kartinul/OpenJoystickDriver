import AppKit
import OpenJoystickDriverKit

/// Reads the exact bundle identifier of the current foreground application.
protocol RemappingForegroundApplicationProviding: Sendable {
  func frontmostBundleIdentifier() -> String?
}

// `@unchecked Sendable` only because of `observerToken`: it is written once in `init` and read
// in `deinit`, so no other thread touches it. The bundle identifier is behind `Locked`.
/// Tracks the foreground application from workspace activation notifications.
///
/// Remapping routing reads the frontmost application for every dispatched input batch;
/// querying `NSWorkspace` there was a measurable share of runtime CPU.
final class WorkspaceRemappingForegroundApplication: RemappingForegroundApplicationProviding,
  @unchecked Sendable
{
  private let notificationCenter: NotificationCenter
  private let bundleIdentifier = Locked<String?>(nil)
  private var observerToken: NSObjectProtocol?

  init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
    self.notificationCenter = notificationCenter
    // Observe before the first read so an activation between the two is not lost.
    observerToken = notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      let application =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      self?.update(application?.bundleIdentifier)
    }
    let initial = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    bundleIdentifier.withLock { if $0 == nil { $0 = initial } }
  }

  deinit { observerToken.map(notificationCenter.removeObserver) }

  func frontmostBundleIdentifier() -> String? { bundleIdentifier.withLock { $0 } }

  private func update(_ bundleIdentifier: String?) {
    self.bundleIdentifier.withLock { $0 = bundleIdentifier }
  }
}

/// Reads the authorization required to synthesize keyboard and pointer events.
protocol RemappingPostEventAccessProviding: Sendable {
  func currentState() -> RemappingPostEventAccessState
}

extension CoreGraphicsPostEventAccess: RemappingPostEventAccessProviding {}

enum RemappingForegroundPolicy {
  static func eligibility(
    for scope: RemappingApplicationScope,
    frontmostBundleIdentifier: String?,
    accessState: RemappingPostEventAccessState,
    outputSuppressed: Bool,
    requiresPostEventAccess: Bool = true
  ) -> RemappingRouteEligibility {
    guard !outputSuppressed else { return .outputSuppressed }
    guard !requiresPostEventAccess || accessState == .granted else {
      return .postEventAccessNotAuthorized
    }
    switch scope {
    case .global: return .eligible
    case .application(let requiredBundleIdentifier):
      return frontmostBundleIdentifier == requiredBundleIdentifier
        ? .eligible : .targetApplicationNotFrontmost
    }
  }
}
