import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct USBControllerScannerTests {
  @Test
  func scannerCarriesObservedTopologyAndCatalogBinding() async throws {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 7,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 9
    )
    let physicalDevice = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x5D,
          interfaceProtocol: 0x01,
          configurationValue: 1,
          hostTransport: .usb,
          usbRoute: .ioUSBHost,
          endpoints: [
            PhysicalEndpointSignature(
              address: 0xA1,
              direction: .in,
              transferType: .interrupt,
              maxPacketSize: 64,
              interval: 4
            ),
            PhysicalEndpointSignature(
              address: 0x17,
              direction: .out,
              transferType: .interrupt,
              maxPacketSize: 64,
              interval: 4
            ),
          ]
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.physicalDevice == physicalDevice)
    guard case .bound(let binding) = description.classification else {
      Issue.record("expected a binding, got \(String(describing: description.classification))")
      return
    }
    #expect(binding.protocolID == .xboxXUSB)
    #expect(binding.variant == .wired)
    #expect(binding.accessBackend == .ioUSBHost)
    #expect(binding.rule == .catalogRecord)
  }

  @Test
  func incompleteDriverKitRouteObservationDoesNotProduceNegativeClassification() async throws {
    let device = USBTransportDevice(
      route: .usbDriverKit,
      serviceID: 42,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 42
    )
    let physicalDevice = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
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
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.physicalDevice == physicalDevice)
    #expect(description.classification == nil)
  }

  @Test
  func driverKitRouteClassifiesWithTheDriverKitBackend() async throws {
    let device = USBTransportDevice(
      route: .usbDriverKit,
      serviceID: 8,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 10
    )
    let physicalDevice = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x47,
          interfaceProtocol: 0xD0,
          hostTransport: .usb,
          accessBackend: .usbDriverKit,
          usbRoute: .usbDriverKit,
          endpoints: [
            PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
          ]
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    guard case .bound(let binding) = description.classification else {
      Issue.record("expected a binding, got \(String(describing: description.classification))")
      return
    }
    #expect(binding.protocolID == .xboxGIP)
    #expect(binding.variant == .usb)
    #expect(binding.accessBackend == .usbDriverKit)
    #expect(binding.rule == .interfaceSignature)
  }

  @Test
  func partialEndpointFieldsDoNotProduceNegativeClassification() async throws {
    let incompleteEndpoints = [
      PhysicalEndpointSignature(direction: .in, transferType: .interrupt),
      PhysicalEndpointSignature(address: 0x81, transferType: .interrupt),
      PhysicalEndpointSignature(address: 0x81, direction: .in),
    ]

    for (index, endpoint) in incompleteEndpoints.enumerated() {
      let device = USBTransportDevice(
        route: .ioUSBHost,
        serviceID: UInt64(20 + index),
        vendorID: 0x045E,
        productID: 0x028E,
        locationID: UInt32(20 + index)
      )
      let physicalDevice = PhysicalDevice(
        serviceIdentity: device.serviceIdentity,
        vendorID: device.vendorID,
        productID: device.productID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x5D,
            interfaceProtocol: 0x01,
            hostTransport: .usb,
            usbRoute: .ioUSBHost,
            endpoints: [endpoint]
          )
        ]
      )
      let descriptions = try await USBControllerScanner.scanVendorSpecific(
        using: ScannerProvider(device: device, observation: physicalDevice)
      )

      let description = try #require(descriptions.first)
      #expect(description.classification == nil)
    }
  }

  @Test
  func hidInterfaceOnRawUSBIsNeverGenericHID() async throws {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 30,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 30
    )
    let physicalDevice = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0x03,
          interfaceSubclass: 0,
          interfaceProtocol: 0,
          hostTransport: .usb,
          usbRoute: .ioUSBHost,
          endpoints: [
            PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt)
          ],
          hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.classification == .unsupported(.noProtocolMatch))
  }

  @Test
  func observedEmptyInterfaceListCanReportUnsupported() async throws {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 40,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 40
    )
    // A parsed configuration with no interfaces is represented by [];
    // unavailable configuration facts are represented by nil.
    let physicalDevice = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: []
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.classification == .unsupported(.noProtocolMatch))
  }

  @Test
  func uncataloguedSignatureDeviceListsItsBindingLikeACatalogRow() async throws {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 41,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 42
    )
    let physicalDevice = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.protocolBinding?.rawValue == "xbox.gip:usb")
    #expect(description.quirks.isEmpty)
    guard case .bound(let binding) = description.classification else {
      Issue.record("expected a binding, got \(String(describing: description.classification))")
      return
    }
    #expect(binding.matchedPredicates == [.deviceClassSignature])
  }
}

private actor ScannerProvider: USBPhysicalDeviceObservationProvider {
  let device: USBTransportDevice
  let observation: PhysicalDevice

  init(device: USBTransportDevice, observation: PhysicalDevice) {
    self.device = device
    self.observation = observation
  }

  func devices() throws -> [USBTransportDevice] { [device] }

  func physicalDeviceObservations() throws -> [PhysicalDevice] { [observation] }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession { ScannerSession() }
}

private final class ScannerSession: USBTransportSession, @unchecked Sendable {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int { 0 }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] { [] }
}
