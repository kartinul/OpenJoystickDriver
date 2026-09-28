import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct UnboundHIDDeviceTests {
  @Test
  func rejectedHIDDeviceIsReportedAndItsClaimReleasedUntilDisconnect() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let connection = Self.connection(vendorID: 0x1234, productID: 0x5678, locationID: 90)

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(
      await manager.unboundDeviceDescriptions() == [
        ApplicationServiceUnboundDevice(
          vendorID: 0x1234,
          productID: 0x5678,
          connection: "USB",
          accessBackend: .ioHID,
          reason: .descriptorContractMismatch,
          candidates: []
        )
      ]
    )
    #expect(await backend.releasedLocations() == [90])

    await manager.handleHIDEvent(.disconnected(connection: connection))
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func rejectedHIDDeviceAtABoundPipelineLocationKeepsTheClaim() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let bound = Self.connection(
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91,
      interface: gamepadHIDInterface(host: .usb)
    )
    await manager.handleHIDEvent(.connected(connection: bound, ownership: .exclusive))
    try #require(await manager.connectedDeviceDescriptions().count == 1)

    let rejected = Self.connection(vendorID: 0x045E, productID: 0x02EA, locationID: 91)
    await manager.handleHIDEvent(.connected(connection: rejected, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().count == 1)
    #expect(
      await manager.unboundDeviceDescriptions().map(\.reason) == [.unsupportedTransportVariant]
    )
    #expect(await backend.releasedLocations().isEmpty)
    await manager.stop()
  }

  @Test
  func stopClearsUnboundDevices() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = Self.connection(vendorID: 0x1234, productID: 0x5678, locationID: 92)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    #expect(await manager.unboundDeviceDescriptions().count == 1)

    await manager.stop()

    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    #expect(await manager.unboundHIDClaims.isEmpty)
  }

  @Test
  func rejectedSiblingOfOneControllerTracksItsBoundPipeline() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let rejected = Self.connection(
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 95,
      serialNumber: "pad-1"
    )
    await manager.handleHIDEvent(.connected(connection: rejected, ownership: .exclusive))
    #expect(await backend.releasedLocations() == [95])

    let bound = Self.connection(
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91,
      serialNumber: "pad-1",
      interface: gamepadHIDInterface(host: .usb)
    )
    await manager.handleHIDEvent(.connected(connection: bound, ownership: .exclusive))
    try #require(await manager.connectedDeviceDescriptions().count == 1)
    #expect(await backend.reacquiredLocations() == [95])

    await manager.handleHIDEvent(.disconnected(connection: bound))
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await backend.releasedLocations() == [95, 95])
    await manager.stop()
  }

  @Test
  func hidAccessFailureClearsUnboundHIDDevices() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = Self.connection(vendorID: 0x1234, productID: 0x5678, locationID: 93)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    #expect(await manager.unboundDeviceDescriptions().count == 1)

    await manager.handleHIDEvent(.accessFailure(.ioReturn(kIOReturnNotPermitted)))

    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func unboundDevicesRoundTripThroughTheStatusPayload() throws {
    let device = ApplicationServiceUnboundDevice(
      vendorID: 0x045E,
      productID: 0x02EA,
      connection: "USB",
      accessBackend: .ioHID,
      reason: .ambiguousProtocolMatch,
      candidates: [.xboxGIP, .hidDescriptor]
    )
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      unboundDevices: [device]
    )
    let decoded = try JSONDecoder().decode(
      ApplicationServiceStatusPayload.self,
      from: JSONEncoder().encode(payload)
    )
    #expect(decoded.unboundDevices == [device])
  }

  private static func connection(
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32,
    serialNumber: String? = nil,
    interface: PhysicalInterfaceSignature = hostHIDInterface(.usb)
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        productName: "Test pad",
        serialNumber: serialNumber,
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [interface]
      ),
      routingLocationID: locationID
    )
  }
}

actor ClaimRecordingHIDAccessBackend: HIDAccessBackend {
  private var released: [UInt32] = []
  private var reacquired: [UInt32] = []
  private var elementValueRoutes: [UInt32] = []

  func releasedLocations() -> [UInt32] { released }
  func elementValueLocations() -> [UInt32] { elementValueRoutes }
  func reacquiredLocations() -> [UInt32] { reacquired }

  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { _ in } }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { [] }

  func setOutputReport(
    locationID _: UInt32,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setOutputReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    locationID _: UInt32,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func getFeatureReport(
    locationID _: UInt32,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func getFeatureReport(
    connection _: HIDDeviceConnection,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func releaseInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    released.append(locationID)
    return .released
  }

  func reacquireInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    reacquired.append(locationID)
    return .reacquired
  }

  func routeElementValues(connection: HIDDeviceConnection) {
    elementValueRoutes.append(connection.routingLocationID)
  }
}
