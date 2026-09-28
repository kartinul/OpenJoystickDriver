import AppKit
import OpenJoystickDriverKit

/// Reads the exact bundle identifier of the current foreground application.
protocol RemappingForegroundApplicationProviding: Sendable {
  func frontmostBundleIdentifier() -> String?
}

/// Tracks the foreground application from workspace activation notifications.
///
/// Remapping routing reads the frontmost application for every dispatched input batch;
/// querying `NSWorkspace` there was a measurable share of runtime CPU.
final class WorkspaceRemappingForegroundApplication: RemappingForegroundApplicationProviding,
  @unchecked Sendable
{
  private let notificationCenter: NotificationCenter
  private let lock = NSLock()
  private var bundleIdentifier: String?
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
    lock.withLock { if bundleIdentifier == nil { bundleIdentifier = initial } }
  }

  deinit { observerToken.map(notificationCenter.removeObserver) }

  func frontmostBundleIdentifier() -> String? { lock.withLock { bundleIdentifier } }

  private func update(_ bundleIdentifier: String?) {
    lock.withLock { self.bundleIdentifier = bundleIdentifier }
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
