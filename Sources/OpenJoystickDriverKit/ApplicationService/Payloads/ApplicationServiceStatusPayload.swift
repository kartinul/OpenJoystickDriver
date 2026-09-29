import Foundation

/// An observed device that no protocol driver bound, with the typed rejection.
public struct ApplicationServiceUnboundDevice: Codable, Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  /// Connection label (e.g. "USB", "Bluetooth").
  public let connection: String
  public let accessBackend: DeviceAccessBackend
  public let reason: ProtocolBindingReason
  /// Protocol families that matched or competed and were rejected, each with its own reason;
  /// empty when none matched.
  public let rejectedCandidates: [ProtocolBindingResult.RejectedCandidate]
  /// Class facts of the interfaces observed when the device was rejected.
  public let interfaces: [ProtocolBindingResult.InterfaceSummary]

  public init(
    vendorID: UInt16,
    productID: UInt16,
    connection: String,
    accessBackend: DeviceAccessBackend,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate],
    interfaces: [ProtocolBindingResult.InterfaceSummary]
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.connection = connection
    self.accessBackend = accessBackend
    self.reason = reason
    self.rejectedCandidates = rejectedCandidates
    self.interfaces = interfaces
  }

  /// The structured, redacted binding decision for this device.
  public var bindingResult: ProtocolBindingResult {
    ProtocolBindingResult(
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      accessBackend: accessBackend,
      interfaces: interfaces
    )
  }
}

extension ApplicationServiceUnboundDevice {
  package init(snapshot: UnboundDeviceSnapshot) {
    self.init(
      vendorID: snapshot.vendorID,
      productID: snapshot.productID,
      connection: snapshot.connection,
      accessBackend: snapshot.accessBackend,
      reason: snapshot.reason,
      rejectedCandidates: snapshot.rejectedCandidates,
      interfaces: snapshot.interfaces
    )
  }
}

/// An observed device the running macOS exposes as a native gamepad, which OJD leaves unbound.
public struct ApplicationServicePassThroughDevice: Codable, Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  /// Connection label (e.g. "USB", "Bluetooth").
  public let connection: String

  public init(vendorID: UInt16, productID: UInt16, connection: String) {
    self.vendorID = vendorID
    self.productID = productID
    self.connection = connection
  }
}

extension ApplicationServicePassThroughDevice {
  package init(snapshot: PassThroughDeviceSnapshot) {
    self.init(
      vendorID: snapshot.vendorID,
      productID: snapshot.productID,
      connection: snapshot.connection
    )
  }
}

/// Status snapshot returned by ``ApplicationServiceClient/getStatus()``.
///
/// Contains the current macOS permission states (as human-readable strings like
/// "granted" or "denied") and descriptions of all connected controllers.
public struct ApplicationServiceStatusPayload: Codable, Sendable {
  /// Exact source and app bundle identity that produced this status snapshot.
  public let buildIdentity: BuildIdentity
  /// Input Monitoring permission state (e.g. "granted", "denied").
  public let inputMonitoring: String
  /// Accessibility permission used to publish an IOHIDUserDevice.
  public let accessibility: String
  /// Structured descriptions of all connected controllers.
  public let connectedDevices: [ApplicationServiceDeviceDescription]
  /// Observed devices that no protocol driver bound.
  public let unboundDevices: [ApplicationServiceUnboundDevice]
  /// Observed devices left to macOS by native pass-through.
  public let passThroughDevices: [ApplicationServicePassThroughDevice]
  /// Whether the user-space virtual gamepad is enabled (IOHIDUserDevice).
  public let userSpaceVirtualDeviceEnabled: Bool?
  /// Status of the user-space virtual gamepad; encoded as its `wireValue` string.
  public let userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus?
  /// Why the stored virtual HID profile overrides cannot be read; nil when they are absent or
  /// valid. While set, every controller selects automatically.
  public let virtualHIDProfileOverrideError: String?

  /// Creates a new ApplicationServiceStatusPayload.
  public init(
    buildIdentity: BuildIdentity = .current(),
    inputMonitoring: String,
    accessibility: String,
    connectedDevices: [ApplicationServiceDeviceDescription],
    unboundDevices: [ApplicationServiceUnboundDevice] = [],
    passThroughDevices: [ApplicationServicePassThroughDevice] = [],
    userSpaceVirtualDeviceEnabled: Bool? = nil,
    userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus? = nil,
    virtualHIDProfileOverrideError: String? = nil
  ) {
    self.buildIdentity = buildIdentity
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
    self.connectedDevices = connectedDevices
    self.unboundDevices = unboundDevices
    self.passThroughDevices = passThroughDevices
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.virtualHIDProfileOverrideError = virtualHIDProfileOverrideError
  }

  private enum CodingKeys: String, CodingKey {
    case buildIdentity
    case inputMonitoring
    case accessibility
    case connectedDevices
    case unboundDevices
    case passThroughDevices
    case userSpaceVirtualDeviceEnabled
    case userSpaceVirtualDeviceStatus
    case virtualHIDProfileOverrideError
  }
}
