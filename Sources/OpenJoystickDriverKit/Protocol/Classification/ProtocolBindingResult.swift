import Foundation

/// The redacted, structured record of one binding decision for diagnostics and support reports.
///
/// It carries observed interface class facts and the classifier's typed outcome only. It never
/// carries a serial number, input state, packet payload, or source provenance. The bound protocol
/// and variant and the applied quirks are reported beside it by the controller description.
public struct ProtocolBindingResult: Codable, Equatable, Sendable {
  public enum Outcome: String, Codable, Sendable {
    case bound
    case unsupported
  }

  /// Class and HID facts of one observed interface. The descriptor is named by its fingerprint
  /// only; its bytes are never carried.
  public struct InterfaceSummary: Codable, Equatable, Sendable {
    /// One HID usage page and usage pair.
    public struct Usage: Codable, Equatable, Sendable {
      public let usagePage: UInt32?
      public let usage: UInt32?
    }

    public let interfaceNumber: UInt8?
    public let alternateSetting: UInt8?
    public let interfaceClass: UInt8?
    public let interfaceSubclass: UInt8?
    public let interfaceProtocol: UInt8?
    public let hostTransport: PhysicalTransport?
    public let primaryUsage: Usage?
    /// Whether the descriptor has a Game Pad or Joystick collection; nil when undecided.
    public let hasGamePadOrJoystickCollection: Bool?
    /// Lowercase SHA-256 of the reported descriptor bytes.
    public let descriptorFingerprint: String?

    public init(_ interface: PhysicalInterfaceSignature) {
      interfaceNumber = interface.interfaceNumber
      alternateSetting = interface.alternateSetting
      interfaceClass = interface.interfaceClass
      interfaceSubclass = interface.interfaceSubclass
      interfaceProtocol = interface.interfaceProtocol
      hostTransport = interface.hostTransport
      let layout = interface.hidLayout
      primaryUsage = layout?.primaryUsage.map { Usage(usagePage: $0.usagePage, usage: $0.usage) }
      hasGamePadOrJoystickCollection = layout?.hasGamePadOrJoystickCollection
      descriptorFingerprint = layout?.descriptorFingerprint
    }
  }

  /// A protocol family that matched or competed but did not bind, with its own reason.
  public struct RejectedCandidate: Codable, Equatable, Sendable {
    public let protocolID: PhysicalProtocolID
    public let reason: ProtocolBindingReason
    /// The catalog record whose row named this family; nil when no row did.
    public let catalogRecordID: String?

    public init(
      protocolID: PhysicalProtocolID,
      reason: ProtocolBindingReason,
      catalogRecordID: String? = nil
    ) {
      self.protocolID = protocolID
      self.reason = reason
      self.catalogRecordID = catalogRecordID
    }
  }

  public let outcome: Outcome
  /// Why the device is not bound; nil when bound.
  public let reason: ProtocolBindingReason?
  public let accessBackend: DeviceAccessBackend
  public let interfaces: [InterfaceSummary]
  /// The classification rule that bound the device; nil when unsupported.
  public let rule: ProtocolBinding.Rule?
  public let matchedPredicates: [ProtocolPredicate]
  /// The applied catalog record, named like its `vvvv-pppp.json` file; nil when none applied.
  public let catalogRecordID: String?
  public let rejectedCandidates: [RejectedCandidate]

  /// The result for a bound device.
  public init(binding: ProtocolBinding, interfaces: [PhysicalInterfaceSignature]) {
    outcome = .bound
    reason = nil
    accessBackend = binding.accessBackend
    self.interfaces = interfaces.map(InterfaceSummary.init)
    rule = binding.rule
    matchedPredicates = binding.matchedPredicates
    catalogRecordID = binding.record?.recordID
    rejectedCandidates = []
  }

  /// The result for a device no driver bound. Each candidate states its own rejection.
  public init(
    reason: ProtocolBindingReason,
    rejectedCandidates: [RejectedCandidate],
    accessBackend: DeviceAccessBackend,
    interfaces: [InterfaceSummary]
  ) {
    outcome = .unsupported
    self.reason = reason
    self.accessBackend = accessBackend
    self.interfaces = interfaces
    rule = nil
    matchedPredicates = []
    catalogRecordID = nil
    self.rejectedCandidates = rejectedCandidates
  }
}
