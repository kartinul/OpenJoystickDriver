import Foundation

/// A validated raw-USB test plan loaded from a canonical controller record.
///
/// The plan uses the runtime's profile construction and driver factory, so a probed
/// record behaves exactly as the runtime would drive it.
public struct ControllerRecordProbePlan: Equatable, Sendable {
  public let name: String
  public let vendorID: UInt16
  public let productID: UInt16
  public let protocolBinding: ProtocolBindingID
  public let transportProfile: DeviceTransportProfile
  public let startupPackets: [GIPStartupPacket]
  public let keepAlivePolicy: GIPKeepAlivePolicy
  private let profile: DeviceRuntimeProfile

  public init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url)) }

  public init(data: Data) throws {
    let profile: DeviceRuntimeProfile
    let document: ControllerRecordDocument
    do {
      document = try JSONDecoder().decode(ControllerRecordDocument.self, from: data)
      profile = try DeviceCatalog.makeRuntimeProfile(document)
    } catch {
      throw ControllerRecordProbeError.invalidProfile("Invalid controller record: \(error)")
    }
    // The signing-free probe drives only the raw-USB Xbox families it can start safely.
    guard [.xboxGIP, .xboxXUSB].contains(profile.physicalProtocolID) else {
      throw ControllerRecordProbeError.unsupportedProtocol(profile.physicalProtocolID.rawValue)
    }
    guard let binding = profile.rawUSBBinding else {
      throw ControllerRecordProbeError.unsupportedProtocol(profile.physicalProtocolID.rawValue)
    }
    vendorID = UInt16(document.vendorID)
    productID = UInt16(document.productID)
    name = String(format: "Controller %04x:%04x", document.vendorID, document.productID)
    protocolBinding = binding
    transportProfile = profile.transportProfile
    startupPackets = profile.physicalProtocolID == .xboxGIP ? profile.gipStartupPackets : []
    keepAlivePolicy = profile.gipKeepAlivePolicy
    self.profile = profile
  }

  /// Builds the record's driver without an observed device, to render the plan. A probe that
  /// writes to a device uses ``makeDriver(for:claimed:)``.
  public func makeUnobservedDriver() -> any PhysicalProtocolDriver {
    let result = ProtocolDriverRegistry.makeUnobservedDriver(
      protocolID: profile.physicalProtocolID,
      variant: variant,
      record: profile,
      identifier: DeviceIdentifier(vendorID: vendorID, productID: productID),
      transportProfile: transportProfile
    )
    guard case .success(let driver) = result else {
      preconditionFailure("validated probe plan has no driver for \(protocolBinding)")
    }
    return driver
  }

  /// Builds the record's driver for one enumerated device through the runtime's validating
  /// factory. `claimed` holds the profile resolved for the device and the facts observed for it;
  /// a claimed interface that violates the family contract fails before any write.
  public func makeDriver(
    for device: USBTransportDevice,
    claimed: USBTransportResolution
  ) -> Result<any PhysicalProtocolDriver, ProtocolBindingReason> {
    let binding = ProtocolBinding(
      protocolID: profile.physicalProtocolID,
      variant: variant,
      accessBackend: DeviceAccessBackend(route: device.route),
      interfaceNumber: transportProfile.interfaceNumber,
      rule: .catalogRecord,
      matchedPredicates: [.catalogIdentity, .catalogAccessPath],
      record: profile
    )
    return ProtocolDriverRegistry().makeDriver(
      for: binding,
      identifier: DeviceIdentifier(
        vendorID: device.vendorID,
        productID: device.productID,
        serialNumber: device.serialNumber,
        locationID: device.locationID
      ),
      claimed: claimed
    )
  }

  /// GIP's variant follows the transport, which is raw USB here.
  private var variant: PhysicalProtocolVariantID? { profile.physicalProtocolVariant ?? .usb }
}

/// Errors reported before the probe opens or writes to a physical device.
public enum ControllerRecordProbeError: Error, Equatable, LocalizedError, Sendable {
  case invalidProfile(String)
  case unsupportedProtocol(String)

  public var errorDescription: String? {
    switch self {
    case .invalidProfile(let message): message
    case .unsupportedProtocol(let binding):
      "The signing-free record probe does not support protocol \(binding)"
    }
  }
}
