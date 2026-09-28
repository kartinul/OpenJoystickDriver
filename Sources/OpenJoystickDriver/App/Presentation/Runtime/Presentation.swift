import Foundation
import OpenJoystickDriverKit

enum RuntimeLoadState: Sendable, Equatable {
  case loading
  case available
  case unavailable(String)
  case error(String)
}

enum RuntimePermissionState: String, Sendable, Equatable {
  case granted
  case denied
  case unknown
  case unavailable
}

struct RuntimePermissionSummary: Sendable, Equatable {
  let inputMonitoring: RuntimePermissionState
  let accessibility: RuntimePermissionState

  init(inputMonitoring: RuntimePermissionState, accessibility: RuntimePermissionState) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
  }

  init(status: ApplicationServiceStatusPayload) {
    self.init(
      inputMonitoring: Self.state(for: status.inputMonitoring),
      accessibility: Self.state(for: status.accessibility)
    )
  }

  init(snapshot: PermissionManager.Snapshot) {
    self.init(
      inputMonitoring: Self.state(for: snapshot.inputMonitoring),
      accessibility: Self.state(for: snapshot.accessibility)
    )
  }

  var isReady: Bool { inputMonitoring == .granted && accessibility == .granted }

  var inputMonitoringLabel: String { RuntimePresentation.permissionLabel(inputMonitoring) }

  var accessibilityLabel: String { RuntimePresentation.permissionLabel(accessibility) }

  static func state(for value: String) -> RuntimePermissionState {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "granted": return .granted
    case "denied": return .denied
    case "unknown": return .unknown
    default: return .unavailable
    }
  }

  static func state(for value: PermissionManager.AccessState) -> RuntimePermissionState {
    switch value {
    case .granted: return .granted
    case .denied: return .denied
    case .unknown: return .unknown
    }
  }
}

enum RuntimeOutputState: String, Sendable, Equatable {
  case ready
  case unavailable
  case error
  case unknown
}

enum RuntimeReadiness: String, Sendable, Equatable {
  case ready
  case needsAttention
  case noController
}

struct RuntimeStatusPresentation: Sendable, Equatable {
  let permissions: RuntimePermissionSummary
  let devices: [ApplicationServiceDeviceDescription]
  /// Why the stored virtual HID profile overrides cannot be read, as reported by the service.
  let virtualHIDProfileOverrideError: String?
  /// Raw value of the retired global controller identity setting the service no longer applies.
  let legacyCompatibilityIdentityRejected: String?
  let outputState: RuntimeOutputState
  let outputDetail: String?
  let postEventAccess: RemappingPostEventAccessState?
  let requiresPostEventAccess: Bool?
  let readiness: RuntimeReadiness

  init(
    payload: ApplicationServiceStatusPayload,
    postEventAccess: RemappingPostEventAccessState? = nil,
    requiresPostEventAccess: Bool? = nil
  ) {
    let permissions = RuntimePermissionSummary(status: payload)
    let outputState: RuntimeOutputState
    if payload.userSpaceVirtualDeviceStatus?.lowercased().hasPrefix("error:") == true {
      outputState = .error
    } else if payload.userSpaceVirtualDeviceEnabled == nil {
      outputState = .unknown
    } else if payload.userSpaceVirtualDeviceEnabled == false {
      outputState = .unavailable
    } else {
      outputState = .ready
    }

    self.permissions = permissions
    self.devices = payload.connectedDevices
    self.virtualHIDProfileOverrideError = payload.virtualHIDProfileOverrideError
    self.legacyCompatibilityIdentityRejected = payload.legacyCompatibilityIdentityRejected
    self.outputState = outputState
    self.outputDetail = RuntimePresentation.outputDetail(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus
    )
    self.postEventAccess = postEventAccess
    self.requiresPostEventAccess = requiresPostEventAccess
    self.readiness = Self.readiness(
      permissions: permissions,
      outputState: outputState,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess,
      devices: payload.connectedDevices
    )
  }

  init(
    permissions: RuntimePermissionSummary,
    devices: [ApplicationServiceDeviceDescription],
    virtualHIDProfileOverrideError: String?,
    legacyCompatibilityIdentityRejected: String?,
    outputState: RuntimeOutputState,
    outputDetail: String?,
    postEventAccess: RemappingPostEventAccessState?,
    requiresPostEventAccess: Bool?,
    readiness: RuntimeReadiness
  ) {
    self.permissions = permissions
    self.devices = devices
    self.virtualHIDProfileOverrideError = virtualHIDProfileOverrideError
    self.legacyCompatibilityIdentityRejected = legacyCompatibilityIdentityRejected
    self.outputState = outputState
    self.outputDetail = outputDetail
    self.postEventAccess = postEventAccess
    self.requiresPostEventAccess = requiresPostEventAccess
    self.readiness = readiness
  }
}

extension RemappingProfile {
  var hasOutputMappings: Bool {
    if gyroOutput.mode != .disabled || !stickMappings.isEmpty || !touchMappings.isEmpty
      || motionTuning.steering != nil
      || layers.contains(where: { $0.motionTuning?.steering != nil })
    {
      return true
    }
    if !bindings.isEmpty || !chords.isEmpty || !sequences.isEmpty { return true }
    return layers.contains { layer in
      !layer.bindings.isEmpty || !layer.chords.isEmpty || !layer.sequences.isEmpty
    }
  }
}

enum RuntimeStatusState: Sendable, Equatable {
  case loading
  case available(RuntimeStatusPresentation)
  case unavailable(String)
  case error(String)
}

enum RuntimeRemappingState: Sendable, Equatable {
  case loading
  case available(ApplicationServiceRemappingSnapshotPayload)
  case unavailable(String)
  case error(String)
}

enum RuntimeActiveProfileState: Sendable, Equatable {
  case loading
  case noProfile
  case profile(String)
  case unavailable(String)
  case error(String)
}

enum RuntimePermissionLoadState: Sendable, Equatable {
  case loading
  case unavailable
  case requesting
  case available(RuntimePermissionSummary)
  case error(String)
}

enum RuntimePostEventAccessLoadState: Sendable, Equatable {
  case loading
  case requesting
  case available(RemappingPostEventAccessState)
  case unavailable(String)
  case error(String)
}

/// One controller's pending or failed virtual HID profile override request.
/// A controller model: the scope of a virtual HID profile override, which the service applies
/// to every connected controller with the same vendor and product.
struct RuntimeControllerModel: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16

  init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  init(_ device: ApplicationServiceDeviceDescription) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }
}

/// The virtual HID profile override request and last failure of one controller model.
struct RuntimeVirtualHIDProfileOverrideState: Sendable, Equatable {
  enum Request: Sendable, Equatable {
    case set(VirtualHIDProfileID)
    case reset

    /// The override the request stores; nil for a reset to automatic selection.
    var requested: VirtualHIDProfileID? {
      guard case .set(let profile) = self else { return nil }
      return profile
    }
  }

  /// The request being applied, or nil when none is in flight.
  var request: Request?
  var failure: String?

  var inFlight: Bool { request != nil }
}

enum RuntimeMutationState: Sendable {
  case idle
  case saving
  case succeeded(profileID: UUID)
  case completed(RuntimeMutationOperation)
  case conflict(profileID: UUID?)
  case error(String)
}

struct RuntimeMutationRequest: Equatable, Sendable {
  let operation: RuntimeMutationOperation
  let id: UUID

  init(operation: RuntimeMutationOperation, id: UUID = UUID()) {
    self.operation = operation
    self.id = id
  }
}

enum RuntimeMutationResult: Equatable, Sendable {
  case succeeded(id: UUID, operation: RuntimeMutationOperation)
  case conflict(id: UUID, operation: RuntimeMutationOperation)
  case failed(id: UUID, operation: RuntimeMutationOperation, message: String)
  case rejected(id: UUID, operation: RuntimeMutationOperation, message: String)

  var id: UUID {
    switch self {
    case .succeeded(let id, _), .conflict(let id, _), .failed(let id, _, _),
      .rejected(let id, _, _):
      return id
    }
  }

  var operation: RuntimeMutationOperation {
    switch self {
    case .succeeded(_, let operation), .conflict(_, let operation), .failed(_, let operation, _),
      .rejected(_, let operation, _):
      return operation
    }
  }

  var request: RuntimeMutationRequest { RuntimeMutationRequest(operation: operation, id: id) }
}

enum RuntimeMutationOperation: Sendable, Equatable {
  case create(profileID: UUID)
  case update(profileID: UUID)
  case importProfile(profileID: UUID)
  case delete(profileID: UUID)
  case activate(profileID: UUID)
  case deactivate(profileID: UUID?)

  var profileID: UUID? {
    switch self {
    case .create(let profileID), .update(let profileID), .importProfile(let profileID),
      .delete(let profileID), .activate(let profileID):
      return profileID
    case .deactivate(let profileID): return profileID
    }
  }
}

enum RuntimeInputCaptureState: Sendable {
  case idle
  case listening(RuntimeDeviceSelector)
  case received(RuntimeDeviceSelector, ControllerState)
  case detected(RuntimeDeviceSelector, ControllerState, RemappingSource)
  case unavailable(RuntimeDeviceSelector, String)
  case error(RuntimeDeviceSelector, String)
}
