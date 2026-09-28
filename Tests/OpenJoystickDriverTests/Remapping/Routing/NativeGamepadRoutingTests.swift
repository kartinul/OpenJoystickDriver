import Foundation
import Testing

@testable import OpenJoystickDriver
@testable import OpenJoystickDriverKit

private final class NativePublicationProbe: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, @unchecked Sendable
{
  private let lock = NSLock()
  private var activationCount = 0
  private var dispatchCount = 0
  var suppressOutput = false
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }
  var publications: Int { lock.withLock { activationCount + dispatchCount } }

  func activate(for identifiers: [DeviceIdentifier]) {
    lock.withLock { activationCount += identifiers.count }
  }
  func activate(controller _: DeviceIdentifier) { lock.withLock { activationCount += 1 } }
  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {
    lock.withLock { dispatchCount += 1 }
  }
  func activateOutput(for _: DeviceIdentifier) { lock.withLock { dispatchCount += 1 } }
  func close() {}
}

/// A natively supported pad is observed: its input reaches remapping, and no virtual gamepad is
/// published for it.
@Suite(.serialized)
struct NativeGamepadRoutingTests {
  @Test
  func automaticIdentityNeverPublishesForANativePad() async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = try await Self.connect(native: true, to: manager, locationID: 181)
    let probe = NativePublicationProbe()
    let automatic = AutomaticUserSpaceOutputDispatcher(
      deviceManager: manager,
      builder: { _ in probe },
      descriptionsProvider: { await manager.connectedDeviceDescriptions() }
    )

    try await automatic.activate(controller: identifier)
    await automatic.dispatch(changes: [.press(.faceSouth)], from: identifier)

    #expect(probe.publications == 0)
    await automatic.close()
    await manager.stop()
  }

  @Test
  func remappingProfileRunsOnANativePadsInput() async throws {
    let profile = Self.profile(policy: .systemInput)
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let manager = DeviceManager(dispatcher: harness.router)
    _ = try await Self.connect(native: true, to: manager, locationID: 182)

    await Self.pressCross(on: manager, locationID: 182)

    #expect(harness.recorder.snapshot().contains { if case .system = $0 { true } else { false } })
    await manager.stop()
    try await harness.router.shutdown()
  }

  @Test
  func noProfileMeansNoDispatchUntilAProfileIsSelected() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    let manager = DeviceManager(dispatcher: harness.router)
    let identifier = try await Self.connect(native: true, to: manager, locationID: 184)
    #expect(!harness.router.wantsObservedInput(from: identifier))

    let profile = Self.profile(policy: .systemInput)
    try await harness.library.create(profile)
    try await harness.library.activate(profileID: profile.id)
    try await harness.router.refresh(identifier)
    #expect(harness.router.wantsObservedInput(from: identifier))

    await Self.pressCross(on: manager, locationID: 184)
    #expect(harness.recorder.snapshot().contains { if case .system = $0 { true } else { false } })
    await manager.stop()
    try await harness.router.shutdown()
  }

  @Test
  func virtualGamepadRemappingIsRejectedForANativePad() async throws {
    let profile = Self.profile(policy: RemappingOutputPolicy(virtualGamepad: .mapped))
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let manager = DeviceManager(dispatcher: harness.router)
    let identifier = try await Self.connect(native: true, to: manager, locationID: 183)

    await Self.pressCross(on: manager, locationID: 183)

    #expect(await harness.router.status(for: identifier)?.eligibility == .physicalInputNotExclusive)
    #expect(!harness.recorder.snapshot().contains { if case .gamepad = $0 { true } else { false } })
    await manager.stop()
    try await harness.router.shutdown()
  }

  private static func connect(
    native: Bool,
    to manager: DeviceManager,
    locationID: UInt32
  ) async throws -> DeviceIdentifier {
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: 0x09CC,
        productName: "Wireless Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            hostTransport: .usb,
            accessBackend: .ioHID,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ],
        nativePassThrough: native
      ),
      routingLocationID: locationID
    )
    await manager.handleHIDEvent(
      .connected(connection: connection, ownership: native ? .unknown : .exclusive)
    )
    return try #require(await manager.pipelines.keys.first { $0.locationID == locationID })
  }

  private static func profile(policy: RemappingOutputPolicy) -> RemappingProfile {
    RemappingProfile(
      name: "Native",
      device: RemappingDeviceScope(vendorID: 0x054C, productID: 0x09CC),
      applicationScope: .application(bundleIdentifier: "com.example.Game"),
      outputPolicy: policy,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
  }

  /// Sends a neutral USB DualShock 4 report, so a slow run that trips input liveness recovers,
  /// then one with Cross held.
  private static func pressCross(on manager: DeviceManager, locationID: UInt32) async {
    for (face, timestamp) in [(UInt8(0x08), UInt8(1)), (0x28, 2)] {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<6, with: [0x01, 0x80, 0x80, 0x80, 0x80, face])
      report[10] = timestamp
      await manager.handleHIDEvent(
        .inputReport(
          locationID: locationID,
          connectionID: UUID(),
          reportID: 0x01,
          data: Data(report)
        )
      )
    }
  }
}
