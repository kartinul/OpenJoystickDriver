import Foundation

/// Redacted serial number state for a HID device.
public enum ApplicationServiceSerialKind: String, Codable, Sendable {
  case none
  case ojdUserSpace
  case present
}

/// Safe (non-sensitive) snapshot of a HID "GamePad" device as seen by IOKit.
public struct ApplicationServiceHIDGamepadSnapshot: Codable, Sendable, Hashable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let product: String?
  public let transport: String?
  public let locationID: UInt32?
  public let serialKind: ApplicationServiceSerialKind
  public let ioUserClass: String?

  /// True if this looks like an OJD app-owned virtual HID device.
  public let isOJDUserSpace: Bool
  /// True if Apple's GameController.framework says this HID device gets a GCController.
  public let isGameControllerSupported: Bool?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    product: String?,
    transport: String?,
    locationID: UInt32?,
    serialKind: ApplicationServiceSerialKind,
    ioUserClass: String?,
    isOJDUserSpace: Bool,
    isGameControllerSupported: Bool? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.transport = transport
    self.locationID = locationID
    self.serialKind = serialKind
    self.ioUserClass = ioUserClass
    self.isOJDUserSpace = isOJDUserSpace
    self.isGameControllerSupported = isGameControllerSupported
  }
}

/// Diagnostics snapshot returned by
/// ``ApplicationServiceProtocol/getVirtualDeviceDiagnostics(reply:)``.
public struct ApplicationServiceVirtualDeviceDiagnosticsPayload: Codable, Sendable {
  public let userSpaceVirtualDeviceEnabled: Bool
  public let userSpaceVirtualDeviceStatus: String
  public let hidGamepads: [ApplicationServiceHIDGamepadSnapshot]

  public init(
    userSpaceVirtualDeviceEnabled: Bool,
    userSpaceVirtualDeviceStatus: String,
    hidGamepads: [ApplicationServiceHIDGamepadSnapshot]
  ) {
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.hidGamepads = hidGamepads
  }
}

/// End-to-end verdict for one virtual-device self-test path.
public enum ApplicationServiceVirtualDeviceSelfTestVerdict: String, Codable, Sendable {
  case passed
  case failed
  case inconclusive
}

/// Result of a short "press buttons now" self-test for virtual device input delivery.
public struct ApplicationServiceVirtualDeviceSelfTestPayload: Codable, Sendable {
  public let seconds: Int
  public let userSpaceValueEvents: Int
  public let userSpaceReportEvents: Int
  public let userSpaceRequired: Bool
  public let userSpaceStatus: String

  public var userSpaceVerdict: ApplicationServiceVirtualDeviceSelfTestVerdict {
    guard userSpaceRequired else { return .inconclusive }
    if userSpaceStatus.hasPrefix("error:") { return .failed }
    if userSpaceValueEvents > 0 || userSpaceReportEvents > 0 { return .passed }
    return .failed
  }

  public var isSuccessful: Bool { userSpaceVerdict == .passed }

  public init(
    seconds: Int,
    userSpaceValueEvents: Int,
    userSpaceReportEvents: Int,
    userSpaceRequired: Bool = true,
    userSpaceStatus: String = "off"
  ) {
    self.seconds = seconds
    self.userSpaceValueEvents = userSpaceValueEvents
    self.userSpaceReportEvents = userSpaceReportEvents
    self.userSpaceRequired = userSpaceRequired
    self.userSpaceStatus = userSpaceStatus
  }
}

/// Discovery route that owns a connected controller pipeline.
public enum ApplicationServiceDeviceDiscoverySource: String, Codable, Sendable {
  case hid
  case rawUSB = "raw-usb"
  case unknown
}

public enum ControllerSessionState: String, Codable, Equatable, Sendable {
  case active
  case suspended
}

public enum ControllerSessionMutationFailure: String, Codable, Equatable, Sendable {
  case notFound = "not-found"
  case alreadySuspended = "already-suspended"
  case alreadyActive = "already-active"
}

public struct ControllerSuspendResult: Codable, Equatable, Sendable {
  public let state: ControllerSessionState
  public let failure: ControllerSessionMutationFailure?

  public init(state: ControllerSessionState, failure: ControllerSessionMutationFailure? = nil) {
    self.state = state
    self.failure = failure
  }

  public var succeeded: Bool { state == .suspended && failure == nil }

}

public struct ControllerResumeResult: Codable, Equatable, Sendable {
  public let state: ControllerSessionState
  public let failure: ControllerSessionMutationFailure?

  public init(state: ControllerSessionState, failure: ControllerSessionMutationFailure? = nil) {
    self.state = state
    self.failure = failure
  }

  public var succeeded: Bool { state == .active && failure == nil }
}

public enum WirelessControllerDisconnectFailure: String, Codable, Equatable, Sendable {
  case notFound = "not-found"
  case notBluetooth = "not-bluetooth"
  case missingAddress = "missing-address"
  case disconnectFailed = "disconnect-failed"
  case timedOut = "timed-out"
}

public enum WirelessControllerDisconnectStage: String, Codable, Equatable, Sendable {
  case releaseHIDClaim = "release-hid-claim"
  case closeBluetoothConnection = "close-bluetooth-connection"
  case confirmBluetoothDisconnection = "confirm-bluetooth-disconnection"
  case restoreHIDClaim = "restore-hid-claim"
  case restoreControllerSession = "restore-controller-session"
}

public struct WirelessControllerDisconnectResult: Codable, Equatable, Sendable {
  public let state: ControllerSessionState
  public let failure: WirelessControllerDisconnectFailure?
  public let failedStage: WirelessControllerDisconnectStage?
  public let systemCode: Int32?
  public let detail: String?
  public let recovery: String?

  public init(
    state: ControllerSessionState,
    failure: WirelessControllerDisconnectFailure? = nil,
    failedStage: WirelessControllerDisconnectStage? = nil,
    systemCode: Int32? = nil,
    detail: String? = nil,
    recovery: String? = nil
  ) {
    self.state = state
    self.failure = failure
    self.failedStage = failedStage
    self.systemCode = systemCode
    self.detail = detail
    self.recovery = recovery
  }

  public var succeeded: Bool { failure == nil }
}

/// Structured description of a connected controller, used in ``ApplicationServiceStatusPayload``.
public struct ApplicationServiceDeviceDescription: Codable, Sendable {
  /// Opaque selector for one connected controller during the current runtime session.
  public let runtimeIdentifier: String
  /// Human-readable controller name.
  public let name: String
  /// USB vendor ID.
  public let vendorID: UInt16
  /// USB product ID.
  public let productID: UInt16
  /// Bound protocol family and resolved variant (e.g. `xbox.gip:usb`, `vendor.flydigi`).
  public let protocolBinding: ProtocolBindingID
  /// Connection type (e.g. "USB", "HID").
  public let connection: String
  /// USB interface number the controller is reached through: the claimed interface of a raw-USB
  /// pipeline, or the parent interface observed for a HID connection. Nil when none was observed.
  public let interfaceNumber: UInt8?
  /// Discovery route that owns the live controller pipeline.
  public let discoverySource: ApplicationServiceDeviceDiscoverySource
  /// Observed physical ownership route used by virtual exposure policy.
  public let physicalOwnership: ControllerOwnershipObservation
  /// Current HID acquisition result; unknown for non-HID discovery routes.
  public let hidInputOwnership: HIDInputOwnership
  /// Duplicate-device risk implied by the current physical ownership observation.
  public let duplicateExposureRisk: DuplicateExposureRisk
  /// USB serial number, or nil if not reported.
  public let serialNumber: String?
  /// Driver-declared quirk IDs from the controller record.
  public let quirks: [String]
  /// The structured, redacted decision that bound this controller.
  public let bindingResult: ProtocolBindingResult
  /// Interrupt IN endpoint address used by USB transports.
  public let inputEndpoint: UInt8
  /// Interrupt OUT endpoint address used by USB transports.
  public let outputEndpoint: UInt8
  /// Whether the USB pipeline calls setConfiguration(1) before claiming.
  public let needsSetConfiguration: Bool
  /// Post-handshake settle delay in milliseconds.
  public let postHandshakeSettleMs: Int
  /// Preferred virtual output backends from the controller record.
  public let preferredBackends: [String]
  /// Exact source-backed motors and lighting features of the active parser.
  public let physicalOutputCapabilities: PhysicalControllerOutputCapabilities
  /// Normalized controls and sample formats the active parser emits for this record.
  public let capabilities: ControllerCapabilities
  /// Link and latest power state of the physical controller.
  public let connectionState: ControllerConnectionState?
  /// Whether OpenJoystickDriver currently admits input and publishes output for this session.
  public let sessionState: ControllerSessionState
  /// Result of the most recent required protocol startup command sequence.
  public let startupCommandStatus: String?
  /// Live report freshness and recovery state for this controller input pipeline.
  public let inputHealth: ControllerInputHealth
  /// Virtual HID profile selection for this controller; set by the service when it reports status.
  public var virtualHIDProfile: ApplicationServiceVirtualHIDProfileStatus?

  /// Creates a new ApplicationServiceDeviceDescription.
  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    protocolBinding: ProtocolBindingID,
    connection: String,
    interfaceNumber: UInt8? = nil,
    discoverySource: ApplicationServiceDeviceDiscoverySource = .unknown,
    physicalOwnership: ControllerOwnershipObservation = .unknown,
    hidInputOwnership: HIDInputOwnership = .unknown,
    duplicateExposureRisk: DuplicateExposureRisk = .unknownOwnership,
    serialNumber: String?,
    quirks: [String] = [],
    bindingResult: ProtocolBindingResult,
    inputEndpoint: UInt8 = 0,
    outputEndpoint: UInt8 = 0,
    needsSetConfiguration: Bool = false,
    postHandshakeSettleMs: Int = 0,
    preferredBackends: [String] = [],
    physicalOutputCapabilities: PhysicalControllerOutputCapabilities = .none,
    capabilities: ControllerCapabilities = ControllerCapabilities(controls: []),
    connectionState: ControllerConnectionState? = nil,
    sessionState: ControllerSessionState = .active,
    startupCommandStatus: String? = nil,
    inputHealth: ControllerInputHealth = ControllerInputHealth(state: .healthy),
    runtimeIdentifier: String? = nil
  ) {
    self.runtimeIdentifier = runtimeIdentifier ?? String(format: "%04X:%04X:M", vendorID, productID)
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.protocolBinding = protocolBinding
    self.connection = connection
    self.interfaceNumber = interfaceNumber
    self.discoverySource = discoverySource
    self.physicalOwnership = physicalOwnership
    self.hidInputOwnership = hidInputOwnership
    self.duplicateExposureRisk = duplicateExposureRisk
    self.serialNumber = serialNumber
    self.quirks = quirks
    self.bindingResult = bindingResult
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleMs = postHandshakeSettleMs
    self.preferredBackends = preferredBackends
    self.physicalOutputCapabilities = physicalOutputCapabilities
    self.capabilities = capabilities
    self.connectionState = connectionState
    self.sessionState = sessionState
    self.startupCommandStatus = startupCommandStatus
    self.inputHealth = inputHealth
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.runtimeIdentifier = try container.decode(String.self, forKey: .runtimeIdentifier)
    self.name = try container.decode(String.self, forKey: .name)
    self.vendorID = try container.decode(UInt16.self, forKey: .vendorID)
    self.productID = try container.decode(UInt16.self, forKey: .productID)
    self.protocolBinding = try container.decode(ProtocolBindingID.self, forKey: .protocolBinding)
    self.connection = try container.decode(String.self, forKey: .connection)
    self.interfaceNumber = try container.decodeIfPresent(UInt8.self, forKey: .interfaceNumber)
    self.discoverySource = try container.decode(
      ApplicationServiceDeviceDiscoverySource.self,
      forKey: .discoverySource
    )
    self.physicalOwnership =
      try container.decodeIfPresent(ControllerOwnershipObservation.self, forKey: .physicalOwnership)
      ?? .unknown
    self.hidInputOwnership =
      try container.decodeIfPresent(HIDInputOwnership.self, forKey: .hidInputOwnership) ?? .unknown
    self.duplicateExposureRisk =
      try container.decodeIfPresent(DuplicateExposureRisk.self, forKey: .duplicateExposureRisk)
      ?? .unknownOwnership
    self.serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    self.quirks = try container.decodeIfPresent([String].self, forKey: .quirks) ?? []
    self.bindingResult = try container.decode(ProtocolBindingResult.self, forKey: .bindingResult)
    self.inputEndpoint = try container.decodeIfPresent(UInt8.self, forKey: .inputEndpoint) ?? 0
    self.outputEndpoint = try container.decodeIfPresent(UInt8.self, forKey: .outputEndpoint) ?? 0
    self.needsSetConfiguration =
      try container.decodeIfPresent(Bool.self, forKey: .needsSetConfiguration) ?? false
    self.postHandshakeSettleMs =
      try container.decodeIfPresent(Int.self, forKey: .postHandshakeSettleMs) ?? 0
    self.preferredBackends =
      try container.decodeIfPresent([String].self, forKey: .preferredBackends) ?? []
    self.physicalOutputCapabilities = try container.decode(
      PhysicalControllerOutputCapabilities.self,
      forKey: .physicalOutputCapabilities
    )
    self.capabilities = try container.decode(ControllerCapabilities.self, forKey: .capabilities)
    self.connectionState = try container.decodeIfPresent(
      ControllerConnectionState.self,
      forKey: .connectionState
    )
    self.sessionState =
      try container.decodeIfPresent(ControllerSessionState.self, forKey: .sessionState) ?? .active
    self.startupCommandStatus = try container.decodeIfPresent(
      String.self,
      forKey: .startupCommandStatus
    )
    self.inputHealth =
      try container.decodeIfPresent(ControllerInputHealth.self, forKey: .inputHealth)
      ?? ControllerInputHealth(state: .healthy)
    self.virtualHIDProfile = try container.decodeIfPresent(
      ApplicationServiceVirtualHIDProfileStatus.self,
      forKey: .virtualHIDProfile
    )
  }
}
