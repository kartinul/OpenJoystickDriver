import Foundation

extension USBTransportProvider {
  /// Completes a raw-USB resolution from the device's own descriptor of configuration 1 when the
  /// passive registry facts carry no usable interface with endpoints: the IORegistry carries
  /// interface class triples but no endpoint descriptors, and an unconfigured device has no
  /// interfaces.
  ///
  /// The descriptor is read without SET_CONFIGURATION, and claimed-interface validation checks it
  /// before any write. The pipeline's open sends the only SET_CONFIGURATION: rows that set it
  /// before the claim already request it, and a device observed unconfigured gets it too, since
  /// none of its interfaces can be claimed otherwise. Explicit catalog endpoint pins stay
  /// authoritative, but a pinned device is read too, so validation can confirm its interface class
  /// and that the pinned endpoints exist. Returns nil when the descriptor cannot be read, so a
  /// later poll retries instead of running on unvalidated or family-default endpoints.
  public func resolveUSBConfiguration(
    _ device: USBTransportDevice,
    passive: USBTransportResolution
  ) async -> USBTransportResolution? {
    let configured = settingConfigurationIfUnconfigured(
      passive.profile,
      observed: passive.physicalDevice
    )
    let passiveResolution = USBTransportResolution(
      profile: configured,
      physicalDevice: passive.physicalDevice
    )
    guard device.route == .ioUSBHost,
      USBDescriptorTransportResolver.discover(
        configured: configured,
        observed: passive.physicalDevice
      ) == nil
    else { return passiveResolution }
    do {
      guard let observed = try await configurationObservation(for: device, configurationValue: 1)
      else {
        print("[USBTransport] USB configuration descriptor unavailable for \(device.serviceID)")
        return nil
      }
      return USBTransportResolution(
        profile: USBDescriptorTransportResolver.resolve(configured: configured, observed: observed),
        physicalDevice: observed
      )
    } catch USBTransportError.notSupported {
      // The provider has no descriptor source; the passive facts are all there is.
      return passiveResolution
    } catch {
      print(
        "[USBTransport] USB configuration descriptor read failed for \(device.serviceID): \(error)"
      )
      return nil
    }
  }
}

private func settingConfigurationIfUnconfigured(
  _ profile: DeviceTransportProfile,
  observed: PhysicalDevice?
) -> DeviceTransportProfile {
  guard !profile.needsSetConfiguration, let observed, (observed.interfaces ?? []).isEmpty,
    (observed.configurationValue ?? 0) == 0
  else { return profile }
  return DeviceTransportProfile(
    inputEndpoint: profile.inputEndpoint,
    outputEndpoint: profile.outputEndpoint,
    interfaceNumber: profile.interfaceNumber,
    alternateSetting: profile.alternateSetting,
    hasInterfaceOverride: profile.hasInterfaceOverride,
    hasEndpointOverride: profile.hasEndpointOverride,
    needsSetConfiguration: true,
    postHandshakeSettleNanoseconds: profile.postHandshakeSettleNanoseconds
  )
}

extension DeviceManager {
  /// The logical-controller key of a raw-USB service claiming the profile's interface.
  static func usbIdentifier(
    for device: USBTransportDevice,
    claiming profile: DeviceTransportProfile
  ) -> DeviceIdentifier {
    DeviceIdentifier(
      vendorID: device.vendorID,
      productID: device.productID,
      serialNumber: device.serialNumber,
      locationID: device.locationID,
      interfaceNumber: profile.interfaceNumber
    )
  }

  func hasUSBPipelineConflict(
    for identifier: DeviceIdentifier,
    service: USBTransportServiceIdentity
  ) -> Bool {
    Self.hasUSBPipelineConflict(
      for: identifier,
      service: service,
      among: pipelines.keys.map { ($0, deviceInfos[$0]?.usbTransportDevice?.serviceIdentity) }
    )
  }

  /// A raw-USB admission conflicts when its exact logical-controller key is already running, or
  /// when the same physical controller runs through another service: another route, another
  /// location, or HID, whose pipelines carry no service. Interfaces of one service never conflict
  /// with each other, so each receiver slot can hold its own pipeline.
  static func hasUSBPipelineConflict(
    for identifier: DeviceIdentifier,
    service: USBTransportServiceIdentity,
    among pipelines: [(key: DeviceIdentifier, service: USBTransportServiceIdentity?)]
  ) -> Bool {
    pipelines.contains { key, keyService in
      key == identifier || keyService != service && isSamePhysicalController(key, identifier)
    }
  }

  /// Whether two keys reached through different services belong to one physical controller: the
  /// same identity with a serial number, or, since a serial-less identity names only a model, the
  /// same identity at the same location. A USB device's HID interfaces report its USB location.
  static func isSamePhysicalController(_ lhs: DeviceIdentifier, _ rhs: DeviceIdentifier) -> Bool {
    lhs.controllerIdentity == rhs.controllerIdentity
      && (lhs.controllerIdentity.identifiesPhysicalDevice || lhs.locationID == rhs.locationID)
  }

  /// The running raw-USB pipeline that serves the same physical controller as a HID key, if any.
  func rawUSBIdentifier(servingSameControllerAs identifier: DeviceIdentifier) -> DeviceIdentifier? {
    pipelines.keys.first {
      deviceInfos[$0]?.usbTransportDevice != nil && Self.isSamePhysicalController($0, identifier)
    }
  }
}
