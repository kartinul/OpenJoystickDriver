/// A device OJD observed but left unbound, with the binding decision that rejected it.
public struct UnboundDeviceSnapshot: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let connection: String
  public let accessBackend: DeviceAccessBackend
  public let reason: ProtocolBindingReason
  public let rejectedCandidates: [ProtocolBindingResult.RejectedCandidate]
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

  public var bindingResult: ProtocolBindingResult {
    ProtocolBindingResult(
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      accessBackend: accessBackend,
      interfaces: interfaces
    )
  }
}
