import Foundation
import OpenJoystickDriverKit

enum SystemExtensionSetupState: Sendable, Equatable {
  case checking
  case missingEmbedded
  case needsActivation
  case replacementNeeded
  case awaitingApproval
  case active
  case failed
  case invalid
}

package protocol SystemExtensionSetupClient: Sendable {
  func inspect() -> ExtensionStatus
  func requestActivation() async -> SystemExtensionSetupRequestResult
  func requestDeactivation() async -> SystemExtensionSetupRequestResult
}

@MainActor
package final class SystemExtensionSetupCoordinator {
  private let client: any SystemExtensionSetupClient
  private var automaticAttempted = false
  private var requestInFlight = false

  private(set) var state: SystemExtensionSetupState = .checking
  private(set) var status: ExtensionStatus = .unavailable

  package init(client: any SystemExtensionSetupClient) { self.client = client }

  func launch() async { await reconcile(trigger: .launch) }
  func foreground() async { await reconcile(trigger: .foreground) }
  func refresh() async { await reconcile(trigger: .refresh) }
  func repair() async { await reconcile(trigger: .repair) }

  func uninstall() async {
    guard !requestInFlight else { return }
    requestInFlight = true
    defer { requestInFlight = false }
    switch await client.requestDeactivation() {
    case .inactive:
      automaticAttempted = true
      state = .needsActivation
    case .active, .awaitingApproval, .failed, .cancelled, .timedOut: state = .failed
    }
  }

  private enum Trigger { case launch, foreground, refresh, repair }

  private func reconcile(trigger: Trigger) async {
    let previousState = state
    status = client.inspect()
    state = Self.state(for: status)
    if (previousState == .awaitingApproval || previousState == .failed)
      && (state == .needsActivation || state == .replacementNeeded) && trigger != .repair
    {
      state = previousState == .awaitingApproval ? .awaitingApproval : .failed
    }
    guard state == .needsActivation || state == .replacementNeeded else { return }
    guard trigger == .repair || !automaticAttempted else { return }
    guard !requestInFlight else { return }
    automaticAttempted = true
    requestInFlight = true
    defer { requestInFlight = false }
    switch await client.requestActivation() {
    case .active: state = .active
    case .inactive: state = .failed
    case .awaitingApproval: state = .awaitingApproval
    case .failed: state = .failed
    case .cancelled: state = .failed
    case .timedOut: state = .failed
    }
  }

  private static func state(for status: ExtensionStatus) -> SystemExtensionSetupState {
    guard status.bundle == .present else {
      return status.bundle == .missing ? .missingEmbedded : .invalid
    }
    switch status.registration {
    case .active:
      guard let embedded = status.embedded, let installed = status.installed else { return .failed }
      return embedded == installed ? .active : .replacementNeeded
    case .inactive, .absent: return .needsActivation
    case .unavailable: return .failed
    }
  }
}
