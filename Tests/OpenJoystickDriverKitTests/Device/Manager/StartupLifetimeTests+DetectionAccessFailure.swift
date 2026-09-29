import Foundation
import IOKit
import Testing

@testable import OpenJoystickDriverKit

extension StartupLifetimeTests {
  @Test
  func HIDAccessFailureTearsDownPhysicalStateAndWaitsForPermissionWatchRetry() async {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 85)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID,
        productName: "Access-failure test controller",
        transportProperty: "USB",
        physicalLocationIdentifier: 85,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingLocationID: 85
    )

    await manager.ensureHIDDetectionState(for: .granted)
    for _ in 0..<500 {
      if await backend.attemptCount() == 1 { break }
      await Task.yield()
    }
    #expect(await backend.attemptCount() == 1)

    await backend.yield(.connected(connection: connection, ownership: .exclusive), attempt: 1)
    for _ in 0..<500 {
      if await manager.pipelines[identifier] != nil { break }
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == connection.connectionID)
    #expect(await manager.pipelines[identifier] != nil)

    await backend.fail(.ioReturn(kIOReturnNotResponding), attempt: 1)
    for _ in 0..<500 {
      if await manager.hidDetectionTask == nil, await manager.deviceInfos[identifier] == nil {
        break
      }
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(await manager.hidDetectionTask == nil)
    #expect(await manager.hidDetectionSessionID == nil)
    #expect(await manager.deviceInfos[identifier] == nil)
    #expect(await manager.pipelines[identifier] == nil)
    #expect(await backend.attemptCount() == 1)

    // The existing permission watcher invokes this again on its next one-second tick.
    await manager.ensureHIDDetectionState(for: .granted)
    for _ in 0..<500 {
      if await backend.attemptCount() == 2 { break }
      await Task.yield()
    }
    #expect(await backend.attemptCount() == 2)
    await backend.fail(.ioReturn(kIOReturnNoDevice), attempt: 2)
    for _ in 0..<500 {
      if await manager.hidDetectionTask == nil { break }
      try? await Task.sleep(nanoseconds: 2_000_000)
    }
    await manager.stop()
  }

  @Test
  func staleDetectionCompletionCannotClearNewerDetectionTask() async {
    let backend = ScriptedHIDAccessBackend(delaysFirstStream: true)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )

    await manager.ensureHIDDetectionState(for: .granted)
    let firstTask = await manager.hidDetectionTask
    for _ in 0..<500 {
      if await backend.attemptCount() == 1 { break }
      await Task.yield()
    }
    #expect(await backend.attemptCount() == 1)

    await manager.ensureHIDDetectionState(for: .denied)
    await manager.ensureHIDDetectionState(for: .granted)
    let secondTask = await manager.hidDetectionTask
    for _ in 0..<500 {
      if await backend.attemptCount() == 2 { break }
      await Task.yield()
    }
    let secondSessionID = await manager.hidDetectionSessionID
    #expect(await backend.attemptCount() == 2)
    #expect(secondSessionID != nil)

    await backend.releaseFirstStream()
    await firstTask?.value
    #expect(await manager.hidDetectionSessionID == secondSessionID)
    #expect(await manager.hidDetectionTask != nil)

    await backend.fail(.ioReturn(kIOReturnAborted), attempt: 2)
    await secondTask?.value
    #expect(await manager.hidDetectionTask == nil)
    #expect(await manager.hidDetectionSessionID == nil)
    await manager.stop()
  }

  @Test
  func staleAccessFailureTeardownCannotRemoveConnectionFromNewDetectionSession() async throws {
    try await verifyNewConnectionSurvivesOldTeardown(trigger: .accessFailure)
  }

  @Test
  func staleDeniedTeardownCannotRemoveConnectionStartedBeforeItResumes() async throws {
    try await verifyNewConnectionSurvivesOldTeardown(trigger: .denied)
  }

  @Test
  func reconnectDuringNeutralizationRetainsNewDeviceInfoAndPipeline() async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "teardown-race",
      locationID: 82
    )
    let oldConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000006",
      productName: "Old DS4 connection"
    )
    let newConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000007",
      productName: "Reconnected DS4"
    )
    await manager.handleHIDEvent(.connected(connection: oldConnection, ownership: .exclusive))
    let oldPipeline = try #require(await manager.pipelines[identifier])
    #expect(!(await oldPipeline.physicalOutputCapabilities()).rumbleMotors.isEmpty)

    let queue = await manager.outputQueueForTest(for: identifier) ?? PhysicalHIDOutputSerialQueue()
    await manager.installOutputQueueForTest(queue, for: identifier)
    let blockerStarted = StartupTestGate()
    let releaseBlocker = StartupTestGate()
    let blockerTask = Task {
      await queue.perform { _ in
        await blockerStarted.open()
        await releaseBlocker.wait()
        return true
      }
    }
    await blockerStarted.wait()

    let detachTask = Task { await manager.handleHIDEvent(.disconnected(connection: oldConnection)) }
    var teardownSuspendedWithOldInfo = false
    for _ in 0..<500 {
      let currentPipeline = await manager.pipelines[identifier]
      let currentConnectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      if currentPipeline == nil, currentConnectionID == oldConnection.connectionID {
        teardownSuspendedWithOldInfo = true
        break
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(teardownSuspendedWithOldInfo)

    let reconnectTask = Task {
      await manager.handleHIDEvent(.connected(connection: newConnection, ownership: .exclusive))
    }
    var reconnectedInfoIsInstalled = false
    for _ in 0..<500 {
      let currentConnectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      let currentPipeline = await manager.pipelines[identifier]
      if currentConnectionID == newConnection.connectionID, currentPipeline != nil {
        reconnectedInfoIsInstalled = true
        break
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(reconnectedInfoIsInstalled)

    await releaseBlocker.open()
    #expect(await blockerTask.value == .completed(true))
    await detachTask.value
    await reconnectTask.value

    #expect(await manager.deviceInfos[identifier]?.physicalDevice == newConnection.physicalDevice)
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == newConnection.connectionID)
    #expect(await manager.pipelines[identifier] !== oldPipeline)
    #expect(await manager.hidOutputQueues[identifier] === queue)
    await manager.stop()
  }
}
