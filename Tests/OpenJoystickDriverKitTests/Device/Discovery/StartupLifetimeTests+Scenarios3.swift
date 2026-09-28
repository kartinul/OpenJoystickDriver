import Foundation
import IOKit
import Testing

@testable import OpenJoystickDriverKit

extension StartupLifetimeTests {
  @Test
  func abortedSameRouteReplacementLetsStaleTeardownClearOnlyItsOrphanedInfo() async throws {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let identifier = DeviceIdentifier(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "teardown-race",
      locationID: 82
    )
    let oldConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000015",
      productName: "Old DS4 connection"
    )
    let abortedConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000016",
      productName: "Aborted DS4 replacement"
    )
    await manager.handleHIDEvent(.connected(connection: oldConnection, ownership: .exclusive))
    let oldPipeline = try #require(await manager.pipelines[identifier])
    #expect(await manager.pipelines[identifier] === oldPipeline)
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: oldConnection, ownership: .exclusive)
    ])
    await backend.enableOutputReports()
    #expect(
      await manager.sendManualRumble(
        for: identifier,
        left: 64,
        right: 0,
        lt: 0,
        rt: 0,
        durationMs: 5_000
      )
    )
    let neutralOutputStarted = StartupTestGate()
    let releaseNeutralOutput = StartupTestGate()
    await backend.blockNextNeutralMotorOutput(
      started: neutralOutputStarted,
      release: releaseNeutralOutput
    )

    let initializationStarted = StartupTestGate()
    let releaseInitialization = StartupTestGate()
    let noncooperativeInitialization = Task {
      await initializationStarted.open()
      await releaseInitialization.wait()
    }
    await manager.installHIDInitializationForTest(
      HIDDeviceInitialization(connection: oldConnection, task: noncooperativeInitialization)
    )
    let teardownTask = Task { await manager.ensureHIDDetectionState(for: .denied) }
    await initializationStarted.wait()
    for _ in 0..<500 {
      if await manager.hidInitializationTasks.isEmpty { break }
      await Task.yield()
    }
    #expect(await manager.hidInitializationTasks.isEmpty)

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

    let replacementTask = Task {
      await manager.handleHIDEvent(.connected(connection: abortedConnection, ownership: .exclusive))
    }
    var replacementSuspendedWithOldInfo = false
    for _ in 0..<500 {
      if await manager.pipelines[identifier] == nil,
        await manager.deviceInfos[identifier]?.hidConnectionID == oldConnection.connectionID
      {
        replacementSuspendedWithOldInfo = true
        break
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(replacementSuspendedWithOldInfo)

    await manager.handleHIDEvent(.disconnected(connection: abortedConnection))
    replacementTask.cancel()
    await releaseBlocker.open()
    #expect(await blockerTask.value == .completed(true))
    await neutralOutputStarted.wait()
    let reportsWhileNeutralOutputIsGated = await backend.recordedOutputReports()
    #expect(reportsWhileNeutralOutputIsGated.count == 2)
    #expect(reportsWhileNeutralOutputIsGated[0].bytes[7] == 64)
    #expect(reportsWhileNeutralOutputIsGated[1].bytes[3] == 0x01)
    #expect(reportsWhileNeutralOutputIsGated[1].bytes[6] == 0)
    #expect(reportsWhileNeutralOutputIsGated[1].bytes[7] == 0)
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == oldConnection.connectionID)
    #expect(await manager.pipelines[identifier] == nil)
    await releaseNeutralOutput.open()
    await replacementTask.value
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == oldConnection.connectionID)
    #expect(await manager.pipelines[identifier] == nil)

    await releaseInitialization.open()
    await noncooperativeInitialization.value
    await teardownTask.value

    #expect(await manager.deviceInfos[identifier] == nil)
    #expect(await manager.pipelines[identifier] == nil)
    #expect(await manager.hidOutputQueues[identifier] == nil)
    await manager.stop()
  }

  @Test
  func newerPendingReconnectWinsWhileReplacementNeutralizationIsSuspended() async throws {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let identifier = DeviceIdentifier(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "teardown-race",
      locationID: 82
    )
    let oldConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000008",
      productName: "Old DS4 connection"
    )
    let replacedConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000009",
      productName: "Superseded reconnect"
    )
    let currentConnection = ds4Connection(
      id: "00000000-0000-0000-0000-00000000000A",
      productName: "Current reconnect"
    )
    await manager.handleHIDEvent(.connected(connection: oldConnection, ownership: .exclusive))
    let oldPipeline = try #require(await manager.pipelines[identifier])
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: oldConnection, ownership: .exclusive)
    ])
    await backend.enableOutputReports()
    #expect(
      await manager.sendManualRumble(
        for: identifier,
        left: 64,
        right: 0,
        lt: 0,
        rt: 0,
        durationMs: 5_000
      )
    )
    await backend.disableOutputReports()
    await backend.clearOutputReports()

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

    await manager.scheduleHIDDeviceInitialization(
      connection: replacedConnection,
      ownership: .exclusive
    )
    var replacementSuspended = false
    for _ in 0..<500 {
      let currentPipeline = await manager.pipelines[identifier]
      let currentConnectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      if currentPipeline == nil, currentConnectionID == oldConnection.connectionID {
        replacementSuspended = true
        break
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(replacementSuspended)
    let supersededInitialization = try #require(
      await manager.hidInitializationTasks[.location(82)]?.task
    )

    await manager.scheduleHIDDeviceInitialization(
      connection: currentConnection,
      ownership: .exclusive
    )
    var currentReconnectInstalled = false
    for _ in 0..<500 {
      let currentConnectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      let currentPipeline = await manager.pipelines[identifier]
      if currentConnectionID == currentConnection.connectionID, currentPipeline != nil {
        currentReconnectInstalled = true
        break
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    #expect(currentReconnectInstalled)
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: currentConnection, ownership: .exclusive)
    ])

    await releaseBlocker.open()
    #expect(await blockerTask.value == .completed(true))
    await supersededInitialization.value

    #expect(
      await manager.deviceInfos[identifier]?.physicalDevice == currentConnection.physicalDevice
    )
    #expect(
      await manager.deviceInfos[identifier]?.hidConnectionID == currentConnection.connectionID
    )
    #expect(await manager.pipelines[identifier] !== oldPipeline)
    #expect(await manager.hidOutputQueues[identifier] === queue)
    #expect(await backend.recordedOutputReports().isEmpty)
    await manager.stop()
  }
}
