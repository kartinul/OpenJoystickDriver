import Testing

@testable import OpenJoystickDriverKit

struct USBPipelineConflictTests {
  private let service = USBTransportServiceIdentity(route: .ioUSBHost, serviceID: 1)
  private let otherService = USBTransportServiceIdentity(route: .ioUSBHost, serviceID: 2)

  private func key(serial: String?, location: UInt32 = 9, interface: UInt8? = 0) -> DeviceIdentifier
  {
    DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0719,
      serialNumber: serial,
      locationID: location,
      interfaceNumber: interface
    )
  }

  @Test
  func interfacesOfOneServiceDoNotConflict() {
    #expect(
      !DeviceManager.hasUSBPipelineConflict(
        for: key(serial: "receiver", interface: 2),
        service: service,
        among: [(key(serial: "receiver", interface: 0), service)]
      )
    )
  }

  @Test
  func exactKeyConflictsWhateverItsService() {
    for existing in [service, otherService, nil] as [USBTransportServiceIdentity?] {
      for serial in ["pad", nil] as [String?] {
        #expect(
          DeviceManager.hasUSBPipelineConflict(
            for: key(serial: serial),
            service: service,
            among: [(key(serial: serial), existing)]
          )
        )
      }
    }
  }

  @Test
  func samePhysicalControllerThroughAnotherServiceOrHIDConflicts() {
    for existing in [otherService, nil] as [USBTransportServiceIdentity?] {
      #expect(
        DeviceManager.hasUSBPipelineConflict(
          for: key(serial: "pad", location: 257, interface: 0),
          service: service,
          among: [(key(serial: "pad", location: 17_825_792, interface: nil), existing)]
        )
      )
    }
  }

  @Test
  func distinctOrSerialLessControllersOnOtherServicesDoNotConflict() {
    #expect(
      !DeviceManager.hasUSBPipelineConflict(
        for: key(serial: "second", location: 2),
        service: service,
        among: [(key(serial: "first", location: 1), otherService)]
      )
    )
    #expect(
      !DeviceManager.hasUSBPipelineConflict(
        for: key(serial: nil, location: 2),
        service: service,
        among: [(key(serial: nil, location: 1), otherService)]
      )
    )
  }

  @Test
  func emptySerialsNameNoPhysicalDevice() {
    #expect(
      !DeviceManager.hasUSBPipelineConflict(
        for: key(serial: "", location: 2),
        service: service,
        among: [(key(serial: "", location: 1), otherService)]
      )
    )
  }

  @Test
  func serialLessPadServedOverHIDConflictsOnlyAtItsLocation() {
    let hid = key(serial: nil, location: 9, interface: nil)
    #expect(
      DeviceManager.hasUSBPipelineConflict(
        for: key(serial: nil, location: 9),
        service: service,
        among: [(hid, nil)]
      )
    )
    #expect(
      !DeviceManager.hasUSBPipelineConflict(
        for: key(serial: nil, location: 10),
        service: service,
        among: [(hid, nil)]
      )
    )
  }

  @Test
  func sameServiceAdmittedTwiceConflicts() async {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 1,
      vendorID: 1_118,
      productID: 721,
      locationID: 9,
      serialNumber: "serial"
    )
    let provider = USBDiscoveryRecordingProvider(devices: [device])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )
    let claimed = DeviceIdentifier(
      vendorID: 1_118,
      productID: 721,
      serialNumber: "serial",
      locationID: 9,
      interfaceNumber: 0
    )

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([claimed]))
    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .retry)
    #expect(await provider.resolutionCount == 1)
    #expect(await manager.connectedDeviceIdentifiers() == [claimed])
    await manager.stop()
  }

  @Test
  func sameSerialFromAnotherServiceConflicts() async {
    let first = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 1,
      vendorID: 1_118,
      productID: 721,
      locationID: 9,
      serialNumber: "serial"
    )
    let second = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 2,
      vendorID: 1_118,
      productID: 721,
      locationID: 10,
      serialNumber: "serial"
    )
    let provider = USBDiscoveryRecordingProvider(devices: [first, second])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    guard case .claimed = await manager.handleUSBDeviceAdded(first, provider: provider) else {
      Issue.record("The first service was not claimed")
      return
    }
    #expect(await manager.handleUSBDeviceAdded(second, provider: provider) == .retry)
    #expect(await provider.resolutionCount == 1)
    await manager.stop()
  }
}
