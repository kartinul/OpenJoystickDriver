import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SupportReportBindingTests {
  private static let catalog = DeviceCatalog()

  @Test
  func boundControllerReportsItsRuleAndCatalogRecord() throws {
    // 045E:028E is a catalogued raw-USB XUSB row.
    let classification = ProtocolClassifier.classify(
      PhysicalDevice(vendorID: 0x045E, productID: 0x028E),
      backend: .ioUSBHost,
      catalog: Self.catalog
    )
    guard case .bound(let binding) = classification else {
      Issue.record("expected a binding, got \(classification)")
      return
    }
    let interface = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x01,
      hostTransport: .usb
    )
    let result = ProtocolBindingResult(binding: binding, interfaces: [interface])
    let controller = try #require(
      report(connected: [description(binding: binding, result: result)]).data.controllers.first
    )

    #expect(controller.protocolBinding == "xbox.xusb:wired")
    let reported = controller.binding
    #expect(reported.outcome == .bound)
    #expect(reported.reason == nil)
    #expect(reported.rule == .catalogRecord)
    #expect(reported.matchedPredicates == [.catalogIdentity, .catalogAccessPath])
    #expect(reported.catalogRecordID == "045e-028e")
    #expect(reported.accessBackend == .ioUSBHost)
    #expect(reported.interfaces == [ProtocolBindingResult.InterfaceSummary(interface)])
    #expect(reported.rejectedCandidates.isEmpty)
  }

  @Test
  func unboundDeviceReportsItsUnsupportedReason() throws {
    let unbound = ApplicationServiceUnboundDevice(
      vendorID: 0x1234,
      productID: 0x5678,
      connection: "USB",
      accessBackend: .ioHID,
      reason: .descriptorContractMismatch,
      rejectedCandidates: [],
      interfaces: [ProtocolBindingResult.InterfaceSummary(hostHIDInterface(.usb))]
    )
    let device = try #require(report(unbound: [unbound]).data.unboundDevices.first)

    #expect((device.vendorID, device.productID, device.connection) == (0x1234, 0x5678, "USB"))
    #expect(device.binding.outcome == .unsupported)
    #expect(device.binding.reason == .descriptorContractMismatch)
    #expect(device.binding.rule == nil)
    #expect(device.binding.matchedPredicates.isEmpty)
    #expect(device.binding.catalogRecordID == nil)
    #expect(device.binding.interfaces.map(\.hostTransport) == [.usb])
  }

  @Test
  func bindingResultCarriesNoSerialOrInputState() throws {
    let secretSerial = "SERIAL-SECRET-456"
    let binding = ProtocolBinding(
      protocolID: .hidDescriptor,
      variant: nil,
      accessBackend: .ioHID,
      interfaceNumber: 0,
      rule: .hidDescriptor,
      matchedPredicates: [.hidDescriptorContract],
      record: nil
    )
    let result = ProtocolBindingResult(
      binding: binding,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
    let connected = ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: binding.id,
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: secretSerial,
      bindingResult: result
    )
    let data = try report(connected: [connected]).encodedJSON()
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(!json.contains(secretSerial))

    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
    let keys = try #require(encoded as? [String: Any]).keys
    #expect(
      Set(keys) == [
        "outcome", "accessBackend", "interfaces", "rule", "matchedPredicates", "rejectedCandidates",
      ]
    )
    let interfaceKeys = try #require((encoded as? [String: Any])?["interfaces"] as? [[String: Any]])
      .flatMap(\.keys)
    // Descriptor metadata only: its fingerprint, never its bytes or report contents.
    #expect(Set(interfaceKeys) == ["hostTransport", "descriptorFingerprint"])
  }

  @Test
  func boundAndUnboundDeviceReportMatchesTheSchemaCheckedFixture() async throws {
    // A signature-bound raw-USB GIP device whose HID interface, observed at the same location,
    // stays unbound with a non-empty rejected-candidate list (see HIDRawUSBDuplicateTests).
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 90,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91
    )
    func observation(_ endpoints: [PhysicalEndpointSignature]?) -> PhysicalDevice {
      PhysicalDevice(
        serviceIdentity: device.serviceIdentity,
        vendorID: device.vendorID,
        productID: device.productID,
        configurationValue: 1,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x47,
            interfaceProtocol: 0xD0,
            endpoints: endpoints
          )
        ]
      )
    }
    let backend = ClaimRecordingHIDAccessBackend()
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: observation(nil),
      configured: observation([
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
      ])
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend),
      usbTransportProvider: provider
    )
    guard case .claimed = await manager.handleUSBDeviceAdded(device, provider: provider) else {
      Issue.record("The raw-USB service was not claimed")
      return
    }
    let hid = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: 91,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingLocationID: 91
    )
    await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive))

    let connected = await manager.connectedDeviceDescriptions()
    let unbound = await manager.unboundDeviceDescriptions()
    await manager.stop()

    #expect(connected.map(\.discoverySource) == [.rawUSB])
    let boundInterfaces = try #require(connected.first).bindingResult.interfaces
    #expect(!boundInterfaces.isEmpty)
    let rejectedCandidates = try #require(unbound.first).bindingResult.rejectedCandidates
    #expect(!rejectedCandidates.isEmpty)

    let encoded = try report(
      connected: connected.map(ApplicationServiceDeviceDescription.init(snapshot:)),
      unbound: unbound.map(ApplicationServiceUnboundDevice.init(snapshot:))
    ).encodedJSON()
    try assertMatchesFixture(encoded)
  }

  /// Compares `encoded` against the checked-in fixture, ignoring the CloudEvents `id`, which is
  /// randomly generated on every encode. Set `OJD_REGENERATE_REPORT_FIXTURE=1` to rewrite it
  /// after intentionally changing the report shape.
  private func assertMatchesFixture(_ encoded: Foundation.Data) throws {
    let fixtureURL = Self.fixtureURL
    if ProcessInfo.processInfo.environment["OJD_REGENERATE_REPORT_FIXTURE"] == "1" {
      try encoded.write(to: fixtureURL)
      return
    }
    let fixture = try Data(contentsOf: fixtureURL)
    #expect(try normalized(encoded) == normalized(fixture))
  }

  private func normalized(_ data: Foundation.Data) throws -> Foundation.Data {
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    // The CloudEvents id is a fresh UUID on every encode; the fixture pins everything else.
    object["id"] = "fixture"
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private static var fixtureURL: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Diagnostics
      .deletingLastPathComponent()  // OpenJoystickDriverKitTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("RepositoryScripts/fixtures/support_report_binding.json")
  }

  private func description(
    binding: ProtocolBinding,
    result: ProtocolBindingResult
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x045E,
      productID: 0x028E,
      protocolBinding: binding.id,
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: result
    )
  }

  private func report(
    connected: [ApplicationServiceDeviceDescription] = [],
    unbound: [ApplicationServiceUnboundDevice] = []
  ) -> SupportReport {
    SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      buildIdentity: BuildIdentity(
        semanticVersion: "0.5.0",
        appBundleVersion: "1",
        sourceCommit: String(repeating: "a", count: 40),
        sourceState: .clean
      ),
      macOSVersion: "26.0.0",
      architecture: "arm64",
      inputMonitoring: .granted,
      applicationServiceInstalled: true,
      applicationServiceConnected: true,
      applicationServiceHealth: nil,
      status: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: connected,
        unboundDevices: unbound
      ),
      virtualDiagnostics: nil
    )
  }
}
