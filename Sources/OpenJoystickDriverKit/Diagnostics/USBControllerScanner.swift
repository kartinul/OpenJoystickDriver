public struct USBControllerDescription: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let bus: String
  public let address: String
  /// Nil fields mean the model has neither a catalog record nor an interface-signature binding.
  /// The catalog record's family and stored variant, or the signature binding's.
  public let protocolBinding: ProtocolBindingID?
  public let inputEndpoint: String?
  public let outputEndpoint: String?
  public let quirks: [String]
  public let physicalDevice: PhysicalDevice?
  /// Nil when the observation lacks the facts needed to classify without guessing.
  public let classification: ProtocolClassification?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    bus: String,
    address: String,
    protocolBinding: ProtocolBindingID?,
    inputEndpoint: String?,
    outputEndpoint: String?,
    quirks: [String],
    physicalDevice: PhysicalDevice? = nil,
    classification: ProtocolClassification? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.bus = bus
    self.address = address
    self.protocolBinding = protocolBinding
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.quirks = quirks
    self.physicalDevice = physicalDevice
    self.classification = classification
  }
}

public protocol USBPhysicalDeviceObservationProvider: USBTransportProvider {
  func physicalDeviceObservations() async throws -> [PhysicalDevice]
}

public enum USBControllerScanner {
  public static func scanVendorSpecific(
    using provider: any USBTransportProvider
  ) async throws -> [USBControllerDescription] {
    let devices = try await provider.devices()
    let observations: [PhysicalDevice]
    if let observingProvider = provider as? any USBPhysicalDeviceObservationProvider {
      observations = try await observingProvider.physicalDeviceObservations()
    } else {
      observations = []
    }
    let registry = ProtocolDriverRegistry()
    var descriptions: [USBControllerDescription] = []
    for device in devices {
      let physicalDevice = observations.first { $0.serviceIdentity == device.serviceIdentity }
      // Endpoints are resolved from the device's configuration descriptor, as runtime binding
      // resolves them; the registry never carries endpoint descriptors.
      let configuration =
        device.route == .ioUSBHost
        ? try? await provider.configurationObservation(for: device, configurationValue: 1) : nil
      descriptions.append(
        description(
          for: device,
          physicalDevice: physicalDevice,
          configuration: configuration,
          registry: registry
        )
      )
    }
    return descriptions
  }

  private static func description(
    for device: USBTransportDevice,
    physicalDevice: PhysicalDevice?,
    configuration: PhysicalDevice?,
    registry: ProtocolDriverRegistry
  ) -> USBControllerDescription {
    let record = registry.record(
      for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
    )
    // An uncatalogued model is admitted by its passive facts, and runtime binding classifies
    // exactly those facts, so its classification needs no completeness gate.
    let classification: ProtocolClassification? = physicalDevice.flatMap { observation in
      guard record == nil || hasCompleteProtocolFacts(observation) else { return nil }
      return registry.classify(observation, backend: DeviceAccessBackend(route: device.route))
    }
    var signatureBinding: ProtocolBinding?
    if record == nil, case .bound(let binding) = classification { signatureBinding = binding }
    let profile = record ?? signatureBinding.flatMap(registry.runtimeProfile(for:))
    let transport = profile.map {
      USBDescriptorTransportResolver.resolve(
        configured: $0.transportProfile,
        observed: configuration ?? physicalDevice
      )
    }
    return USBControllerDescription(
      vendorID: device.vendorID,
      productID: device.productID,
      bus: device.route.rawValue,
      address: String(device.serviceID),
      protocolBinding: record?.rawUSBBinding ?? signatureBinding?.id,
      inputEndpoint: transport.map { String($0.inputEndpoint, radix: 16) },
      outputEndpoint: transport.map { String($0.outputEndpoint, radix: 16) },
      quirks: profile?.quirks.map(\.rawValue) ?? [],
      physicalDevice: physicalDevice,
      classification: classification
    )
  }

  private static func hasCompleteProtocolFacts(_ device: PhysicalDevice) -> Bool {
    guard let interfaces = device.interfaces else { return false }
    // The probe preserves nil (configuration unavailable) separately from an
    // observed empty interface list (parsed configuration with no interfaces).
    if interfaces.isEmpty { return true }
    return interfaces.allSatisfy { interface in
      guard interface.interfaceNumber != nil, interface.alternateSetting != nil,
        interface.interfaceClass != nil, interface.interfaceSubclass != nil,
        interface.interfaceProtocol != nil, let endpoints = interface.endpoints
      else { return false }
      return endpoints.allSatisfy {
        $0.address != nil && $0.direction != nil && $0.transferType != nil
      }
    }
  }
}
