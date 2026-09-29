import Foundation
import IOKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct TransportFacadeTests {
  @Test
  func facadeExposesPassiveObservationCapabilityWithoutChangingAdmissionOwnership() {
    let provider: any USBPhysicalDeviceObservationProvider =
      OpenJoystickDriverUSBTransportProvider()
    _ = provider
    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [device(route: .ioUSBHost, serviceID: 1, vendorID: 0xFFFF, productID: 1)],
        driverKit: [],
        supportedRawUSBModels: [],
        requiredDriverKitModels: []
      ).isEmpty
    )
  }

  @Test
  func defaultProviderResolutionRetainsConfiguredProfileWithoutInventingFacts() async {
    let provider = FakeUSBTransportProvider()
    let configured = DeviceTransportProfile.gipDefault

    #expect(
      await provider.resolveTransport(
        for: device(route: .ioUSBHost, serviceID: 1),
        configured: configured
      ) == USBTransportResolution(profile: configured)
    )
  }

  @Test
  func driverKitResolutionDoesNotUseDescriptorRouteFallback() {
    let configured = DeviceTransportProfile.gipDefault
    let observation = PhysicalDevice(
      vendorID: 0x045E,
      productID: 0x0B12,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 3,
          interfaceClass: 0xFF,
          endpoints: [
            PhysicalEndpointSignature(address: 0x84, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(address: 0x04, direction: .out, transferType: .interrupt),
          ]
        )
      ]
    )

    #expect(
      OpenJoystickDriverUSBTransportProvider.resolveTransportProfile(
        route: .usbDriverKit,
        configured: configured,
        observation: observation
      ) == configured
    )
  }

  @Test
  func facadeResolutionUsesCompletePassiveInterruptPair() {
    let configured = DeviceTransportProfile.gipDefault
    let observation = PhysicalDevice(
      vendorID: 0x3537,
      productID: 0x1010,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 2,
          alternateSetting: 1,
          interfaceClass: 0xFF,
          endpoints: [
            PhysicalEndpointSignature(address: 0x84, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(address: 0x04, direction: .out, transferType: .interrupt),
          ]
        )
      ]
    )

    let resolved = OpenJoystickDriverUSBTransportProvider.resolveTransportProfile(
      route: .ioUSBHost,
      configured: configured,
      observation: observation
    )

    #expect(resolved.interfaceNumber == 2)
    #expect(resolved.alternateSetting == 1)
    #expect(resolved.inputEndpoint == 0x84)
    #expect(resolved.outputEndpoint == 0x04)
  }

  @Test
  func driverKitResolutionReturnsLimitedObservationWithoutDirectProbe() async throws {
    let device = device(
      route: .usbDriverKit,
      serviceID: 42,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 77,
      observedPhysicalLocationIdentifier: 77,
      productName: "GameSir G7 SE",
      serialNumber: "serial"
    )
    let observation = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      productName: device.productName,
      serialNumber: device.serialNumber,
      physicalLocationIdentifier: 77,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbDriverKit,
          usbRoute: .usbDriverKit
        )
      ]
    )
    let directProbeCalls = ObservationCallCounter()
    let direct = FakeUSBTransportProvider()
    let driverKit = FakeUSBObservationProvider(devices: [device], observations: [observation])
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: direct,
      usbDriverKitProvider: driverKit,
      supportedRawUSBModels: [USBTransportModel(device)],
      requiredDriverKitModels: []
    ) { _ in
      directProbeCalls.increment()
      return nil
    }
    let configured = DeviceTransportProfile.gipDefault

    let resolution = await provider.resolveTransport(for: device, configured: configured)
    #expect(resolution == USBTransportResolution(profile: configured, physicalDevice: observation))
    #expect(resolution.physicalDevice?.interfaces?.first?.interfaceNumber == nil)
    #expect(resolution.physicalDevice?.interfaces?.first?.endpoints == nil)
    #expect(try await provider.physicalDeviceObservations() == [observation])
    #expect(directProbeCalls.calls == 0)
    #expect(await direct.openCount == 0)
  }

  @Test
  func driverKitObservationRejectsDifferentServiceIdentity() async throws {
    let device = device(route: .usbDriverKit, serviceID: 42)
    let mismatchedObservation = PhysicalDevice(
      serviceIdentity: USBTransportServiceIdentity(route: .usbDriverKit, serviceID: 43),
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbDriverKit,
          usbRoute: .usbDriverKit
        )
      ]
    )
    let directProbeCalls = ObservationCallCounter()
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(),
      usbDriverKitProvider: FakeUSBObservationProvider(
        devices: [device],
        observations: [mismatchedObservation]
      ),
      supportedRawUSBModels: [USBTransportModel(device)],
      requiredDriverKitModels: []
    ) { _ in
      directProbeCalls.increment()
      return nil
    }
    let configured = DeviceTransportProfile.gipDefault

    #expect(
      await provider.resolveTransport(for: device, configured: configured)
        == USBTransportResolution(profile: configured)
    )
    #expect(try await provider.physicalDeviceObservations().isEmpty)
    #expect(directProbeCalls.calls == 0)
  }

  @Test
  func mapsUnsupportedAndBadArgumentToEquivalentUnsupportedTransportErrors() {
    #expect(IOUSBHostTransportProvider.transportError(kIOReturnUnsupported) == .notSupported)
    #expect(IOUSBHostTransportProvider.transportError(kIOReturnBadArgument) == .notSupported)
  }

  @Test
  func mapsNotRespondingToDisconnectedSession() {
    #expect(IOUSBHostTransportProvider.transportError(kIOReturnNotResponding) == .disconnected)
    #expect(
      IOUSBHostTransportProvider.transportError(
        NSError(domain: NSMachErrorDomain, code: Int(kIOReturnNotResponding))
      ) == .disconnected
    )
  }

  func device(
    route: USBTransportRoute,
    serviceID: UInt64,
    vendorID: UInt16 = 0x1234,
    productID: UInt16 = 0x5678,
    locationID: UInt32 = 1,
    observedPhysicalLocationIdentifier: UInt32? = nil,
    productName: String? = nil,
    serialNumber: String? = nil
  ) -> USBTransportDevice {
    USBTransportDevice(
      route: route,
      serviceID: serviceID,
      vendorID: vendorID,
      productID: productID,
      locationID: locationID,
      observedPhysicalLocationIdentifier: observedPhysicalLocationIdentifier,
      productName: productName,
      serialNumber: serialNumber
    )
  }
}

private final class ObservationCallCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var countValue = 0

  var calls: Int { lock.withLock { countValue } }

  func increment() { lock.withLock { countValue += 1 } }
}
