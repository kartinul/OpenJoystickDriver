import Foundation

extension DeviceManager {
  enum DiscoverySource {
    case hid
    case rawUSB(route: USBTransportRoute)

    var requiresInputMonitoring: Bool {
      if case .hid = self { return true }
      return false
    }

    var applicationServiceValue: ApplicationServiceDeviceDiscoverySource {
      switch self {
      case .hid: .hid
      case .rawUSB: .rawUSB
      }
    }

    var ownershipObservation: ControllerOwnershipObservation {
      switch self {
      case .hid: .nativeHIDVisible
      case .rawUSB(.ioUSBHost): .exclusiveRawUSB
      case .rawUSB(.usbDriverKit): .driverKitOwnedUSB
      }
    }
  }

  struct DeviceInfo {
    let name: String
    let connection: String
    let serialNumber: String?
    let discoverySource: DiscoverySource
    let binding: ProtocolBinding
    var hidInputOwnership: HIDInputOwnership = .unknown
    let physicalDevice: PhysicalDevice?
    let hidConnectionID: UUID?
    /// Exact enumerated service snapshot used for USB route ownership, not descriptor evidence.
    let usbTransportDevice: USBTransportDevice?

    init(
      name: String,
      connection: String,
      serialNumber: String?,
      discoverySource: DiscoverySource,
      binding: ProtocolBinding,
      hidInputOwnership: HIDInputOwnership = .unknown,
      physicalDevice: PhysicalDevice? = nil,
      hidConnectionID: UUID? = nil,
      usbTransportDevice: USBTransportDevice? = nil
    ) {
      self.name = name
      self.connection = connection
      self.serialNumber = serialNumber
      self.discoverySource = discoverySource
      self.binding = binding
      self.hidInputOwnership = hidInputOwnership
      self.physicalDevice = physicalDevice
      self.hidConnectionID = hidConnectionID
      self.usbTransportDevice = usbTransportDevice
    }

    var ownershipObservation: ControllerOwnershipObservation {
      if physicalDevice?.nativePassThrough == true { return .nativeGamepad }
      if case .hid = discoverySource, hidInputOwnership == .exclusive { return .exclusiveHID }
      return discoverySource.ownershipObservation
    }
  }

  /// Start device detection and input processing.
  public func start() async {
    guard !isStopping else { return }
    isStarted = true
    // A start requested during system sleep runs when the system wakes.
    guard !isSystemSleeping else { return }
    let startGeneration = lifecycleGeneration
    let state = await permissionManager.checkAccess().inputMonitoring
    guard !isStopping, lifecycleGeneration == startGeneration else { return }
    switch state {
    case .unknown, .denied:
      if state == .denied {
        print("[DeviceManager] Input Monitoring denied" + " - running in detect-only mode")
        print(
          "[DeviceManager] Open System Settings" + " > Privacy > Input Monitoring"
            + " to grant access"
        )
      } else {
        print("[DeviceManager] Input Monitoring not yet granted" + " - running in detect-only mode")
        print(
          "[DeviceManager] Use the app's Request Access action" + " to show the native macOS prompt"
        )
      }
    case .granted: print("[DeviceManager] Input Monitoring granted")
    }

    if usbTransportProvider != nil, detectionTasks.isEmpty {
      detectionTasks = [Task { await self.runUSBDetection() }]
    } else if usbTransportProvider == nil {
      detectionTasks = []
    }
    await ensureHIDDetectionState(for: state)
    guard !isStopping, lifecycleGeneration == startGeneration else { return }
    startPermissionWatch()

    print("[DeviceManager] Started" + " - dual detection active")
  }

  func startPermissionWatch() {
    guard permissionWatchTask == nil else { return }
    permissionWatchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let currentState = await self.permissionManager.checkAccess().inputMonitoring
        await self.ensureHIDDetectionState(for: currentState)
        try? await Task.sleep(nanoseconds: devicePermissionWatchNanoseconds)
      }
    }
  }

  /// Tears down every controller session as if each controller were unplugged.
  ///
  /// Controllers re-attach through ordinary hot-plug detection after `systemDidWake`.
  public func systemWillSleep(session: DeviceManagerSystemPowerEventSession? = nil) async {
    guard session?.isActive ?? true, !isSystemSleeping else { return }
    // Recorded even before the first start() or during stop(), so a later start() waits for wake.
    isSystemSleeping = true
    guard isStarted, !isStopping else { return }
    isStopping = true
    await tearDownControllerSessions()
    isStopping = false
    print("[DeviceManager] Suspended for system sleep")
  }

  /// Restarts detection for a manager that was started before or during sleep.
  public func systemDidWake(session: DeviceManagerSystemPowerEventSession? = nil) async {
    guard session?.isActive ?? true, isSystemSleeping, !isStopping else { return }
    isSystemSleeping = false
    if isStarted { await start() }
  }

  /// Returns the latest controller state for a device matched by vendor and product ID.
  ///
  /// Returns nil if no pipeline is active for the device.
  public func controllerState(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil
  ) async -> ControllerState? {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier)
    else { return nil }
    return await pipelines[key]?.inputState()
  }

  /// Returns the ownership evidence for the exact connected device identifier.
  ///
  /// Missing identifiers intentionally fail closed to unknown ownership.
  public func ownershipObservation(
    for identifier: DeviceIdentifier
  ) -> ControllerOwnershipObservation { deviceInfos[identifier]?.ownershipObservation ?? .unknown }

  /// Returns recent raw USB packets for a device matched by vendor and product ID.
  ///
  /// Returns an empty array if no pipeline is active for the device.
  public func packetLog(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil
  ) async -> [PacketLogEntry] {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier)
    else { return [] }
    return await pipelines[key]?.getPacketLog() ?? []
  }

  /// Sends a short physical-controller rumble command for a matched USB device.
  /// Used by the application service to report its live device list.
  public func connectedDeviceDescriptions() async -> [ApplicationServiceDeviceDescription] {
    var descriptions: [ApplicationServiceDeviceDescription] = []
    for id in Array(pipelines.keys) {
      if let description = await deviceDescription(forPipeline: id) {
        descriptions.append(description)
      }
    }
    return descriptions
  }

  /// Describes one connected controller, matched exactly or by runtime identity.
  ///
  /// Output routing calls this per input report, so it builds only the requested description.
  public func deviceDescription(
    for identifier: DeviceIdentifier
  ) async -> ApplicationServiceDeviceDescription? {
    // Identifiers without a serial or location share the model-only token; only exact keys match.
    let key =
      pipelines[identifier] != nil
      ? identifier
      : identifier.locationID != nil || identifier.controllerIdentity.serialNumber?.isEmpty == false
        ? pipelines.keys.first { $0.runtimeIdentifier == identifier.runtimeIdentifier } : nil
    guard let key else { return nil }
    return await deviceDescription(forPipeline: key)
  }

  private func deviceDescription(
    forPipeline id: DeviceIdentifier
  ) async -> ApplicationServiceDeviceDescription? {
    // A pipeline is registered only after its DeviceInfo; a missing one is mid-teardown.
    guard let pipeline = pipelines[id], let info = deviceInfos[id] else { return nil }
    let record = protocolDriverRegistry.runtimeProfile(for: info.binding)
    // A raw-USB pipeline runs on the profile resolved from the device's descriptor.
    let transportProfile =
      info.usbTransportDevice != nil ? pipeline.transportProfile : record?.transportProfile
    let ownership = info.ownershipObservation
    // A HID key carries an interface only for a protocol role; show the observed one for all.
    let observedInterface: UInt8? =
      if case .hid = info.discoverySource {
        info.physicalDevice?.interfaces?.first?.interfaceNumber
      } else { id.interfaceNumber }
    return ApplicationServiceDeviceDescription(
      name: info.name,
      vendorID: id.controllerIdentity.vendorID,
      productID: id.controllerIdentity.productID,
      protocolBinding: info.binding.id,
      connection: info.connection,
      interfaceNumber: observedInterface,
      discoverySource: info.discoverySource.applicationServiceValue,
      physicalOwnership: ownership,
      hidInputOwnership: info.hidInputOwnership,
      duplicateExposureRisk: ControllerExposureDecision.decide(
        ownership: ownership,
        intent: .outputDisabled
      ).duplicateRisk,
      serialNumber: info.serialNumber,
      quirks: record?.quirks.map(\.rawValue) ?? [],
      inputEndpoint: transportProfile?.inputEndpoint ?? 0,
      outputEndpoint: transportProfile?.outputEndpoint ?? 0,
      needsSetConfiguration: transportProfile?.needsSetConfiguration ?? false,
      postHandshakeSettleMs: Int(
        (transportProfile?.postHandshakeSettleNanoseconds ?? 0)
          / deviceDiscoveryNanosecondsPerMillisecond
      ),
      preferredBackends: record?.preferredBackends.map(\.rawValue) ?? [],
      physicalOutputCapabilities: await pipeline.physicalOutputCapabilities(),
      capabilities: protocolDriverRegistry.capabilities(
        await pipeline.capabilities(),
        record: record
      ),
      connectionState: await pipeline.connectionState(
        binding: info.binding,
        interface: info.physicalDevice?.interfaces?.first
      ),
      sessionState: await pipeline.controllerSessionState(),
      startupCommandStatus: await pipeline.startupCommandStatus(),
      inputHealth: await pipeline.inputHealth(),
      runtimeIdentifier: id.runtimeIdentifier
    )
  }

  /// Returns live identifiers for connected controller pipelines.
  public func connectedDeviceIdentifiers() -> [DeviceIdentifier] { Array(pipelines.keys) }

  /// Returns controllers whose sessions can currently publish compatibility output.
  public func activeDeviceIdentifiers() async -> [DeviceIdentifier] {
    var identifiers: [DeviceIdentifier] = []
    for (identifier, pipeline) in pipelines where await pipeline.controllerSessionState() == .active
    { identifiers.append(identifier) }
    return identifiers
  }
}
