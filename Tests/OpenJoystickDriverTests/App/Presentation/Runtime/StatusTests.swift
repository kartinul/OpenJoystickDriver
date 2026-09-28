import Combine
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized)
struct StatusTests {
  @Test
  func translatesStatus() async throws {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-7"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.readiness == .ready)
    #expect(RuntimePresentation.keyboardSystemSymbolName(.a) == nil)
  }

  @Test
  func statusReadinessWaitsForPostEventAccess() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-8"
    )
    let profile = makeProfile(name: "Mapped")
    let activeProfile = ApplicationServiceRemappingActiveProfilePayload(
      vendorID: profile.device.vendorID,
      productID: profile.device.productID,
      profileID: profile.id,
      profileName: profile.name,
      applicationScope: profile.applicationScope
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      ),
      snapshotPayload: snapshot(
        profiles: [profile],
        activeProfiles: [activeProfile],
        postEventAccess: .notAuthorized
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == true)
    #expect(status.readiness == .needsAttention)
  }

  @Test
  func liveStatusRefreshPublishesControllerDisconnectionWithoutLoadingTheUI() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-live"
    )
    let connected = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [device],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready"
    )
    let disconnected = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready"
    )
    let gateway = GatewayStub(statusPayload: connected)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    await viewModel.refresh()
    await gateway.setStatusPayload(disconnected)

    await viewModel.refreshLiveStatus()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected live status to remain available")
      return
    }
    #expect(status.devices.isEmpty)
  }

  @Test
  func liveStatusFailureRetainsLastKnownControllerState() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-retained"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    await viewModel.refresh()
    await gateway.setStatusShouldFail(true)

    await viewModel.refreshLiveStatus()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected the last available status to remain visible")
      return
    }
    #expect(status.devices.map(\.runtimeIdentifier) == [device.runtimeIdentifier])
  }

  @Test
  @MainActor
  func controllerInventoryRefreshQueuesASequentialTrailingRequest() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let viewModel = RuntimeViewModel(gateway: gateway)

    let first = Task { await viewModel.refreshControllerInventory() }
    await gateway.waitForStatusCall(count: 1)
    let second = Task { await viewModel.refreshControllerInventory() }
    await gateway.resumeNextStatusRead()
    await gateway.waitForStatusCall(count: 2)
    await gateway.resumeNextStatusRead()
    await first.value
    await second.value

    #expect(await gateway.statusCallCount == 2)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    #expect(await gateway.remappingSnapshotCallCount == 0)
  }

  @Test
  @MainActor
  func inventoryRefreshQueuedDuringLiveRefreshRunsAtTheTrailingEdge() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let viewModel = RuntimeViewModel(gateway: gateway)

    let liveRefresh = Task { await viewModel.refreshLiveStatus() }
    await gateway.waitForStatusCall(count: 1)
    let inventoryRefresh = Task { await viewModel.refreshControllerInventory() }

    #expect(await gateway.statusCallCount == 1)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    await gateway.resumeNextStatusRead()
    await gateway.waitForStatusCall(count: 2)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    let ds4 = ApplicationServiceDeviceDescription(
      name: "DualShock 4",
      vendorID: 0x054C,
      productID: 0x09CC,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "Bluetooth",
      serialNumber: nil,
      runtimeIdentifier: "ds4-bluetooth"
    )
    await gateway.setStatusPayload(
      ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [ds4],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      )
    )
    await gateway.resumeNextStatusRead()
    _ = await liveRefresh.value
    await inventoryRefresh.value
    #expect(await gateway.statusCallCount == 2)
    guard case .available(let status) = viewModel.statusState else {
      Issue.record("Expected the trailing inventory to publish available status")
      return
    }
    #expect(status.devices.map(\.runtimeIdentifier) == [ds4.runtimeIdentifier])
  }

  @Test
  @MainActor
  func controllersAndMenuBarUseTheSameScopedRefreshCoordinator() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let runtime = RuntimeViewModel(gateway: gateway)
    let controllers = ControllersViewModel(runtime: runtime)
    let menuBar = MenuBarViewModel(runtime: runtime)

    controllers.refresh()
    await gateway.waitForStatusCall(count: 1)
    let menuRefresh = Task { await menuBar.refreshLiveStatus() }

    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    await gateway.resumeNextStatusRead()
    await gateway.waitForStatusCall(count: 2)
    await gateway.resumeNextStatusRead()
    _ = await menuRefresh.value
    #expect(await gateway.statusCallCount == 2)
  }

  @Test
  @MainActor
  func unchangedLiveStatusRefreshDoesNotRepublishObservableState() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    await viewModel.refresh()
    var invalidations = 0
    let observation = viewModel.objectWillChange.sink { invalidations += 1 }

    let statusChanged = await viewModel.refreshLiveStatus()

    #expect(!statusChanged)
    #expect(invalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func livePollingDoesNotCancelTheFullProfilesRefresh() async {
    let gateway = GatewayStub(statusReadDelayNanoseconds: 100_000_000)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let fullRefresh = Task { await viewModel.refresh() }
    await Task.yield()

    await viewModel.refreshLiveStatus()
    await fullRefresh.value

    guard case .available = viewModel.remappingState else {
      Issue.record("Expected profiles to finish loading")
      return
    }
  }

  @Test
  @MainActor
  func liveStatusRefreshPublishesActiveProfileChanges() async {
    let profile = makeProfile(name: "Desktop")
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [profile]))
    let viewModel = RuntimeViewModel(gateway: gateway)
    await viewModel.refresh()
    let activeProfile = ApplicationServiceRemappingActiveProfilePayload(
      vendorID: 0x1234,
      productID: 0x5678,
      profileID: profile.id,
      profileName: profile.name,
      applicationScope: .global
    )
    await gateway.setSnapshotPayload(snapshot(profiles: [profile], activeProfiles: [activeProfile]))

    let statusChanged = await viewModel.refreshLiveStatus()

    guard case .available(let current) = viewModel.remappingState else {
      Issue.record("Expected the remapping snapshot to remain available")
      return
    }
    #expect(statusChanged)
    #expect(current.activeProfiles.map(\.profileID) == [profile.id])
  }

  @Test
  func statusReadinessIgnoresPostEventAccessWithoutActiveMappings() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-9"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      ),
      snapshotPayload: snapshot(profiles: [], postEventAccess: .notAuthorized)
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == false)
    #expect(status.readiness == .ready)
  }

  @Test
  func statusReadinessRemainsUnknownBeforeRemappingSnapshot() {
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready"
    )
    let presentation = RuntimeStatusPresentation(payload: payload, postEventAccess: .granted)

    #expect(presentation.requiresPostEventAccess == nil)
    #expect(presentation.readiness == .needsAttention)
  }
}
