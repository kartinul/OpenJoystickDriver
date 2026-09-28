import Foundation

extension ProtocolClassifier {
  /// Xbox One devices also report the GIP triple in the device descriptor. An unconfigured device
  /// exposes no interfaces, so the device triple is the only signature fact available before
  /// configuration 1 is set.
  static let deviceSignature = InterfaceSignature(
    protocolID: .xboxGIP,
    variant: .usb,
    interfaceClass: 0xFF,
    interfaceSubclass: 0x47,
    interfaceProtocol: 0xD0,
    requiredInterfaceNumber: 0
  )

  /// Whether passive facts carry a known Xbox USB signature on an interface or in the device
  /// descriptor, whatever the configuration state.
  static func carriesSignature(_ device: PhysicalDevice) -> Bool {
    hasDeviceSignature(device)
      || (device.interfaces ?? []).contains { interface in
        signatures.contains { $0.matches(interface) }
      }
  }

  /// Binds the device-descriptor GIP triple only for an unconfigured device with no interface
  /// facts. The binding claims the signature's data interface after configuration 1 is set, and
  /// claimed-interface validation must then observe it before any protocol write.
  static func classifyDeviceSignature(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    guard hasDeviceSignature(device), (device.interfaces ?? []).isEmpty,
      (device.configurationValue ?? 0) == 0
    else { return nil }
    guard backend != .ioHID else {
      return .unsupported(
        .unsupportedTransportVariant,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: deviceSignature.protocolID,
          reason: .unsupportedTransportVariant
        )
      )
    }
    return .bound(
      ProtocolBinding(
        protocolID: deviceSignature.protocolID,
        variant: deviceSignature.variant,
        accessBackend: backend,
        interfaceNumber: deviceSignature.requiredInterfaceNumber,
        rule: .interfaceSignature,
        matchedPredicates: [.deviceClassSignature],
        record: nil
      )
    )
  }

  private static func hasDeviceSignature(_ device: PhysicalDevice) -> Bool {
    device.deviceClass == deviceSignature.interfaceClass
      && device.deviceSubclass == deviceSignature.interfaceSubclass
      && device.deviceProtocol == deviceSignature.interfaceProtocol
  }
}
