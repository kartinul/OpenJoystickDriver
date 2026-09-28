import Combine
import Foundation
import OpenJoystickDriverKit

struct ScopedRefresh: OptionSet {
  let rawValue: UInt8

  static let inventory = Self(rawValue: 1 << 0)
  static let live = Self(rawValue: 1 << 1)
}

@MainActor
final class RuntimeViewModel: ObservableObject {
  let gateway: any ApplicationServiceGateway

  @Published
  var loadState: RuntimeLoadState = .loading
  @Published
  var statusState: RuntimeStatusState = .loading
  @Published
  var remappingState: RuntimeRemappingState = .loading
  @Published
  var permissionState: RuntimePermissionLoadState = .unavailable
  @Published
  var postEventAccessState: RuntimePostEventAccessLoadState = .loading
  /// Virtual HID profile override requests keyed by controller runtime identifier.
  @Published
  var virtualHIDProfileOverrideStates:
    [RuntimeControllerModel: RuntimeVirtualHIDProfileOverrideState] = [:]
  @Published
  var mutationState: RuntimeMutationState = .idle
  @Published
  var profileRecoveryInFlight = false
  @Published
  var inputCaptureState: RuntimeInputCaptureState = .idle
  @Published
  var supportDiagnosticsState: RuntimeSupportDiagnosticsState = .idle
  @Published
  var supportReportState: RuntimeSupportReportState = .idle
  @Published
  var supportLogsState: RuntimeSupportLogsState = .idle
  @Published
  var lastError: String?
  /// Why the latest background status read failed while the last controller list stays visible.
  @Published
  var liveStatusError: String?
  @Published
  var activeMutationOperation: RuntimeMutationOperation?
  @Published
  var activeMutationID: UUID?
  @Published
  var lastMutationOperation: RuntimeMutationOperation?
  @Published
  var lastMutationID: UUID?
  @Published
  private(set) var systemExtensionSetupState: SystemExtensionSetupState = .checking
  @Published
  var controllerInventoryGeneration = 0
  var isScopedRefreshInFlight = false
  let scopedRefreshInFlightPublisher = CurrentValueSubject<Bool, Never>(false)

  var refreshGeneration = 0
  var liveStatusGeneration = 0
  var permissionRefreshGeneration = 0
  var postEventAccessGeneration = 0
  var authoritativePermissionSummary: RuntimePermissionSummary?
  var authoritativePostEventAccess: RemappingPostEventAccessState?
  var inputGeneration = 0
  var supportDiagnosticsGeneration = 0
  var supportReportGeneration = 0
  var supportLogsGeneration = 0
  var mutationInFlight = false
  var fullRefreshInFlight = false
  var pendingScopedRefreshes: ScopedRefresh = []
  var controllerRuntimeIdentifiers: [String] = []
  var scopedRefreshWaiters: [CheckedContinuation<Void, Never>] = []
  var exclusiveOperationWaiters: [CheckedContinuation<Void, Never>] = []
  private let systemExtensionSetup: SystemExtensionSetupCoordinator

  init(
    gateway: any ApplicationServiceGateway,
    systemExtensionSetup: SystemExtensionSetupCoordinator = SystemExtensionSetupCoordinator()
  ) {
    self.gateway = gateway
    self.systemExtensionSetup = systemExtensionSetup
  }

  func startSystemExtensionSetup() async {
    await systemExtensionSetup.launch()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  func refreshSystemExtensionSetup() async {
    await systemExtensionSetup.refresh()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  func repairSystemExtension() async {
    await systemExtensionSetup.repair()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  func uninstallSystemExtension() async {
    await systemExtensionSetup.uninstall()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  func refresh() async {
    await waitForScopedRefreshCompletion()
    await waitForExclusiveOperationCompletion()
    refreshGeneration += 1
    let generation = refreshGeneration
    fullRefreshInFlight = true
    defer {
      if generation == refreshGeneration {
        fullRefreshInFlight = false
        resumeExclusiveOperationWaiters()
        schedulePendingScopedRefresh()
      }
    }
    await refreshSystemExtensionSetup()
    liveStatusGeneration += 1
    let statusGeneration = liveStatusGeneration
    loadState = .loading
    statusState = .loading
    remappingState = .loading
    permissionRefreshGeneration += 1
    let permissionGeneration = permissionRefreshGeneration
    postEventAccessGeneration += 1
    let postEventGeneration = postEventAccessGeneration
    authoritativePermissionSummary = nil
    authoritativePostEventAccess = nil
    permissionState = .loading
    postEventAccessState = .loading
    lastError = nil
    liveStatusError = nil
    var loadedAny = false

    do {
      let payload = try await gateway.status()
      guard generation == refreshGeneration, statusGeneration == liveStatusGeneration else {
        return
      }
      let permissions: RuntimePermissionSummary
      if permissionGeneration == permissionRefreshGeneration {
        permissions = RuntimePermissionSummary(status: payload)
        authoritativePermissionSummary = permissions
      } else {
        // A newer permission request owns the visible permission state.  Until its response is
        // available, replace the payload's old value with an honest checking state.
        permissions =
          authoritativePermissionSummary
          ?? RuntimePermissionSummary(inputMonitoring: .unknown, accessibility: .unknown)
      }
      let presentation = RuntimeStatusPresentation(payload: payload).applyingPermissions(
        permissions
      )
      statusState = .available(presentation)
      publishControllerInventory(payload.connectedDevices)
      if permissionGeneration == permissionRefreshGeneration {
        permissionState = .available(permissions)
      }
      loadedAny = true
    } catch {
      guard generation == refreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      statusState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      if permissionGeneration == permissionRefreshGeneration { permissionState = .error(message) }
      lastError = message
    }

    do {
      let snapshot = try await gateway.remappingSnapshot()
      guard generation == refreshGeneration else { return }
      remappingState = .available(snapshot)
      let postEventAccess: RemappingPostEventAccessState?
      if postEventGeneration == postEventAccessGeneration {
        let currentPostEventAccess = snapshot.postEventAccess
        postEventAccess = currentPostEventAccess
        authoritativePostEventAccess = currentPostEventAccess
        postEventAccessState = .available(currentPostEventAccess)
      } else {
        // A newer access request owns the visible state.  Do not let this older snapshot roll its
        // result back while the newer request is loading or has already completed.
        postEventAccess = authoritativePostEventAccess
      }
      updateStatusRemappingSnapshot(snapshot, postEventAccess: postEventAccess)
      loadedAny = true
    } catch {
      guard generation == refreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      remappingState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      if postEventGeneration == postEventAccessGeneration {
        postEventAccessState =
          RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      }
      lastError = lastError ?? message
    }

    guard generation == refreshGeneration else { return }
    loadState =
      loadedAny
      ? .available
      : .unavailable(
        lastError
          ?? OJDLocalized.string(
            "error.notAvailable",
            fallback: "OpenJoystickDriver isn't available right now."
          )
      )
  }

  func refreshPermissions() async {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .loading
    updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
    do {
      let payload = try await gateway.status()
      guard generation == permissionRefreshGeneration else { return }
      let presentation = RuntimeStatusPresentation(payload: payload)
      permissionState = .available(presentation.permissions)
      authoritativePermissionSummary = presentation.permissions
      updateStatusPermissions(presentation.permissions)
    } catch {
      guard generation == permissionRefreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
      lastError = message
    }
  }

  @discardableResult
  func requestPermissions() async -> RuntimePermissionSummary? {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
    do {
      let snapshot = try await gateway.requestPermissions()
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      lastError = nil
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
      lastError = message
      return nil
    }
  }

  @discardableResult
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async -> RuntimePermissionSummary? {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
    do {
      let snapshot = try await gateway.requestPermission(requirement)
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      lastError = nil
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
      lastError = message
      return nil
    }
  }

  @discardableResult
  func requestPostEventAccess() async -> RemappingPostEventAccessState? {
    postEventAccessGeneration += 1
    let generation = postEventAccessGeneration
    authoritativePostEventAccess = nil
    postEventAccessState = .requesting
    updateStatusPostEventAccess(nil)
    do {
      let state = try await gateway.requestRemappingPostEventAccess()
      guard generation == postEventAccessGeneration else { return nil }
      postEventAccessState = .available(state)
      authoritativePostEventAccess = state
      updateStatusPostEventAccess(state)
      lastError = nil
      return state
    } catch {
      guard generation == postEventAccessGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
      lastError = message
      return nil
    }
  }

  func refreshPostEventAccess() async {
    postEventAccessGeneration += 1
    let generation = postEventAccessGeneration
    authoritativePostEventAccess = nil
    postEventAccessState = .loading
    updateStatusPostEventAccess(nil)
    do {
      let state = try await gateway.remappingPostEventAccess()
      guard generation == postEventAccessGeneration else { return }
      postEventAccessState = .available(state)
      authoritativePostEventAccess = state
      updateStatusPostEventAccess(state)
    } catch {
      guard generation == postEventAccessGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
      lastError = message
    }
  }

}
