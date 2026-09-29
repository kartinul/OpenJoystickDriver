import Foundation
import IOKit
import Testing

@testable import OpenJoystickDriverKit

private actor DeferredPowerEventInvocationGate {
  private var isPaused = false
  private var isReleased = false
  private var pauseContinuation: CheckedContinuation<Void, Never>?
  private var reachedContinuation: CheckedContinuation<Void, Never>?

  func pauseUntilReleased() async {
    isPaused = true
    reachedContinuation?.resume()
    reachedContinuation = nil
    guard !isReleased else { return }
    await withCheckedContinuation { pauseContinuation = $0 }
  }

  func waitUntilPaused() async {
    guard !isPaused else { return }
    await withCheckedContinuation { reachedContinuation = $0 }
  }

  func release() {
    isReleased = true
    pauseContinuation?.resume()
    pauseContinuation = nil
  }
}

private final class WirelessDisconnectProbe: WirelessControllerDisconnecting, @unchecked Sendable {
  private let lock = NSLock()
  private let outcome: WirelessControllerDisconnectOutcome
  private var addresses: [String] = []

  init(outcome: WirelessControllerDisconnectOutcome) { self.outcome = outcome }

  func disconnect(
    address: String,
    timeoutNanoseconds _: UInt64
  ) async -> WirelessControllerDisconnectOutcome {
    await Task.yield()
    lock.withLock { addresses.append(address) }
    return outcome
  }

  var calls: [String] { lock.withLock { addresses } }
}

private final class AbsoluteStickParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan(inputReportLivenessTimeoutNanoseconds: 1_000_000_000)
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// Each report carries the full right stick; report 1 pushes it right, any other centers it.
  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    ControllerEvent(data.first == 1 ? [.rightStick(x: 1, y: 0)] : [], at: receivedAt.nanoseconds)
  }
}

struct ControllerSessionTests {
  @Test
  func absoluteSnapshotsCenterTheStickWithoutAReleaseDelta() async {
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 1, productID: 2),
      transport: .hid(locationID: 6),
      driver: AbsoluteStickParser(),
      dispatcher: output,
      uptimeNanoseconds: ManualUptime().now
    )
    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([2]))

    #expect(output.snapshot().states == [snapshot(.rightStick(x: 1, y: 0)), .neutral])
    await pipeline.stop()
  }

  @Test(arguments: [
    (WirelessControllerDisconnectOutcome.disconnected, nil as WirelessControllerDisconnectFailure?),
    (
      WirelessControllerDisconnectOutcome.failed(kIOReturnError),
      WirelessControllerDisconnectFailure.disconnectFailed
    ), (WirelessControllerDisconnectOutcome.timedOut, WirelessControllerDisconnectFailure.timedOut),
  ])
  func wirelessDisconnectSuspendsBeforeReturning(
    outcome: WirelessControllerDisconnectOutcome,
    expectedFailure: WirelessControllerDisconnectFailure?
  ) async throws {
    let probe = WirelessDisconnectProbe(outcome: outcome)
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      wirelessControllerDisconnector: probe
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Wireless Controller",
            serialNumber: "aa-bb-cc-dd-ee-ff",
            transportProperty: "Bluetooth",
            physicalLocationIdentifier: 71,
            interfaces: [hostHIDInterface(.bluetoothClassic)]
          ),
          routingLocationID: 71,
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)

    let result = await manager.disconnectWirelessController(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )

    #expect(result.state == (expectedFailure == nil ? .suspended : .active))

    #expect(result.failure == expectedFailure)
    switch outcome {
    case .failed(let code):
      #expect(result.failedStage == .closeBluetoothConnection)
      #expect(result.systemCode == code)
      #expect(result.detail?.contains(String(code)) == true)
    case .timedOut:
      #expect(result.failedStage == .confirmBluetoothDisconnection)
      #expect(result.recovery != nil)
    case .disconnected, .stillConnected: break
    }
    #expect(probe.calls == ["AA:BB:CC:DD:EE:FF"])
    await manager.stop()
  }

  @Test(arguments: [
    ("USB", "AA:BB:CC:DD:EE:FF", WirelessControllerDisconnectFailure.notBluetooth),
    ("Bluetooth", nil as String?, WirelessControllerDisconnectFailure.missingAddress),
  ])
  func wirelessDisconnectRejectsInvalidPhysicalSelectionWithoutSuspending(
    connection: String,
    serialNumber: String?,
    expectedFailure: WirelessControllerDisconnectFailure
  ) async throws {
    let probe = WirelessDisconnectProbe(outcome: .disconnected)
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      wirelessControllerDisconnector: probe
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Controller",
            serialNumber: serialNumber,
            transportProperty: connection,
            physicalLocationIdentifier: 72,
            interfaces: [
              hostHIDInterface(HIDDeviceStream.hostTransport(forTransportProperty: connection))
            ]
          ),
          routingLocationID: 72,
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)

    let result = await manager.disconnectWirelessController(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )

    #expect(result.state == .active)
    #expect(result.failure == expectedFailure)
    #expect(probe.calls.isEmpty)
    await manager.stop()
  }

  @Test
  func suspensionNeutralizesHeldInputAndIgnoresReportsUntilResume() async {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: 1),
      driver: DualShock4Driver(),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x28, timestamp: 1))

    #expect(await pipeline.suspendControllerSession())
    #expect(await pipeline.controllerSessionState() == .suspended)
    #expect(await pipeline.inputState().isEffectivelyNeutral)
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x48, timestamp: 2))
    #expect(await pipeline.inputState().isEffectivelyNeutral)

    let suspended = output.snapshot()
    #expect(suspended.stopped == [identifier])
    #expect(suspended.states.last?.pressed.isEmpty == true)

    #expect(await pipeline.resumeControllerSession())
    #expect(await pipeline.controllerSessionState() == .active)
    await pipeline.stop()
  }

  @Test
  func suspendedControllersRemainInInventoryButAreNotVirtualOutputTargets() async throws {
    let manager = DeviceManager(dispatcher: ControllerSessionOutputProbe())
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Controller",
            transportProperty: "USB",
            physicalLocationIdentifier: 73,
            interfaces: [hostHIDInterface(.usb)]
          ),
          routingLocationID: 73,
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(await manager.activeDeviceIdentifiers().count == 1)

    _ = await manager.suspendController(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )

    #expect(await manager.connectedDeviceDescriptions().count == 1)
    #expect(await manager.activeDeviceIdentifiers().isEmpty)
    await manager.stop()
  }

  @Test
  func delayedPowerEventFromStoppedSessionCannotMutateRestartedManager() async {
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      hidManager: HIDManager(backend: RecoveryHIDBackend())
    )
    let stoppedSession = DeviceManagerSystemPowerEventSession()
    let invocationGate = DeferredPowerEventInvocationGate()
    let delayedSleep = Task {
      await invocationGate.pauseUntilReleased()
      await manager.systemWillSleep(session: stoppedSession)
    }

    await invocationGate.waitUntilPaused()
    await manager.stop()
    stoppedSession.invalidate()
    await manager.start()
    let restartedGeneration = await manager.lifecycleGeneration

    await invocationGate.release()
    await delayedSleep.value
    #expect(!(await manager.isSystemSleeping))
    #expect(await manager.lifecycleGeneration == restartedGeneration)

    let currentSession = DeviceManagerSystemPowerEventSession()
    await manager.systemWillSleep(session: currentSession)
    #expect(await manager.isSystemSleeping)
    await manager.systemDidWake(session: currentSession)
    #expect(!(await manager.isSystemSleeping))

    currentSession.invalidate()
    await manager.stop()
  }
}
