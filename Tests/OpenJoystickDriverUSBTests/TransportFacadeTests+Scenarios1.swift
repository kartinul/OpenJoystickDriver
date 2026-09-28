import Foundation
import IOKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

extension TransportFacadeTests {
  @Test
  func accessibleThirdPartyDeviceUsesDirectIOUSBHost() {
    let direct = device(route: .ioUSBHost, serviceID: 1, vendorID: 0x054C, productID: 0x0268)

    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [],
        supportedRawUSBModels: [USBTransportModel(direct)],
        requiredDriverKitModels: []
      ) == [direct]
    )
  }

  @Test
  func entitlementRestrictedModelNeverFallsBackToDirectIOUSBHost() {
    let direct = device(route: .ioUSBHost, serviceID: 1, vendorID: 0x045E, productID: 0x0B12)

    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [],
        supportedRawUSBModels: [USBTransportModel(direct)],
        requiredDriverKitModels: [USBTransportModel(vendorID: 0x045E, productID: 0x0B12)]
      ).isEmpty
    )
  }

  @Test
  func observedDriverKitOwnerWinsOnlyForTheSamePhysicalDevice() {
    let directClaimed = device(
      route: .ioUSBHost,
      serviceID: 1,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 7
    )
    let driverKit = device(
      route: .usbDriverKit,
      serviceID: 2,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 7
    )
    let anotherDirect = device(
      route: .ioUSBHost,
      serviceID: 3,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 8
    )

    let selected = OpenJoystickDriverUSBTransportProvider.selectDevices(
      direct: [directClaimed, anotherDirect],
      driverKit: [driverKit],
      supportedRawUSBModels: [USBTransportModel(directClaimed)],
      requiredDriverKitModels: []
    )

    #expect(selected == [driverKit, anotherDirect])
  }

  @Test
  func oneDiscoveryBackendCanOperateWhenTheOtherIsUnavailable() async throws {
    let directDevice = device(route: .ioUSBHost, serviceID: 1)
    let direct = FakeUSBTransportProvider(devicesResult: .success([directDevice]))
    let unavailable = FakeUSBTransportProvider(devicesResult: .failure(.disconnected))
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: direct,
      usbDriverKitProvider: unavailable,
      supportedRawUSBModels: [USBTransportModel(directDevice)],
      requiredDriverKitModels: []
    )

    #expect(try await provider.devices() == [directDevice])
  }

  @Test
  func openDispatchesByRecordedRouteWithoutFallback() async {
    let direct = FakeUSBTransportProvider(openResult: .failure(.accessDenied))
    let driverKit = FakeUSBTransportProvider()
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: direct,
      usbDriverKitProvider: driverKit,
      supportedRawUSBModels: [USBTransportModel(vendorID: 0x1234, productID: 0x5678)],
      requiredDriverKitModels: []
    )

    do {
      _ = try await provider.open(
        device(route: .ioUSBHost, serviceID: 1),
        options: USBTransportOpenOptions(interfaceNumber: 2)
      )
      Issue.record("Expected the selected IOUSBHost backend to fail")
    } catch { #expect(error as? USBTransportError == .accessDenied) }
    #expect(await direct.openCount == 1)
    #expect(await driverKit.openCount == 0)
  }

  @Test
  func directDiscoveryUsesDeviceServiceBeforeInterfacesExist() {
    let devices = IOUSBHostTransportProvider.devices(from: [
      IOUSBHostDeviceFacts(
        serviceID: 10,
        vendorID: 0x1234,
        productID: 0x5678,
        locationID: 9,
        productName: "Controller",
        serialNumber: "serial"
      )
    ])

    #expect(
      devices == [
        device(
          route: .ioUSBHost,
          serviceID: 10,
          vendorID: 0x1234,
          productID: 0x5678,
          locationID: 9,
          observedPhysicalLocationIdentifier: 9,
          productName: "Controller",
          serialNumber: "serial"
        )
      ]
    )
    #expect(devices.first?.observedPhysicalLocationIdentifier == 9)
  }

}
