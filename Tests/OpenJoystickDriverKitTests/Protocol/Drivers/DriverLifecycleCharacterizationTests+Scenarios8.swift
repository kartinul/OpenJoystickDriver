import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// HID step ordering through DeviceManager, recorded by `ScriptedHIDAccessBackend`. The recorder
// keeps output and feature reports in separate lists and neither records nor answers feature
// reads, so each list's order is pinned but interleaving across the lists is not observable.
extension DriverLifecycleCharacterizationTests {
  struct HIDStartupRecording {
    let backend: ScriptedHIDAccessBackend
    let manager: DeviceManager
    let connection: HIDDeviceConnection
  }

  /// Connects one catalog HID controller over `transport` and runs the startup path to its end.
  /// `interface` defaults to a descriptor-contract gamepad interface.
  func startHIDController(
    _ subject: Subject,
    transport: String,
    locationID: UInt32,
    interface: PhysicalInterfaceSignature? = nil
  ) async -> HIDStartupRecording {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: subject.identifier.controllerIdentity.vendorID,
        productID: subject.identifier.controllerIdentity.productID,
        productName: "Characterized controller",
        transportProperty: transport,
        physicalLocationIdentifier: locationID,
        interfaces: [interface ?? gamepadHIDInterface(host: subject.host)]
      ),
      routingLocationID: locationID
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    return HIDStartupRecording(backend: backend, manager: manager, connection: connection)
  }

  func recordedSteps(_ recording: HIDStartupRecording) async -> [String] {
    let outputs = await recording.backend.recordedOutputReports()
    let features = await recording.backend.recordedFeatureReports()
    return ["outputs=\(outputs.count)"] + outputs.flatMap(render) + ["features=\(features.count)"]
      + features.flatMap(render)
  }

  func dualShock4BluetoothStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.dualShock4Bluetooth,
      transport: "Bluetooth",
      locationID: 201
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  func sixaxisBluetoothStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.sixaxisBluetooth,
      transport: "Bluetooth",
      locationID: 202
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  /// Startup includes the three 200 ms recovery rounds; the controller answers no reads.
  func switchBluetoothStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.switchBluetooth,
      transport: "Bluetooth",
      locationID: 203
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  /// Startup, then the presence path after the dongle reports a connected controller, on dongle
  /// slot 1 as `hid-steam.c` lays it out (a Steam role needs its feature report).
  func steamDonglePresenceSteps() async -> [String] {
    let recording = await startHIDController(
      Self.steamDongle,
      transport: "USB",
      locationID: 204,
      interface: steamHIDInterface(number: 1)
    )
    let startup = await recordedSteps(recording)
    await recording.manager.handleHIDEvent(
      .inputReport(
        locationID: 204,
        connectionID: recording.connection.connectionID,
        reportID: 1,
        data: ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02)
      )
    )
    let connected = await recordedSteps(recording)
    await recording.manager.stop()
    return ["startup"] + startup + ["connected"] + connected
  }

  /// Read before the first 500 ms heartbeat fires, so the periodic output is not in the list.
  func gameSirEnhancedHIDStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.gameSirEnhancedHID,
      transport: "USB",
      locationID: 205
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }
}
