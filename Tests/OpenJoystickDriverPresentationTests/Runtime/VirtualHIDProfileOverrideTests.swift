import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct VirtualHIDProfileOverrideTests {
  private static let model = RuntimeControllerModel(vendorID: 0x1234, productID: 0x5678)

  private static func device(
    runtimeIdentifier: String = "session-device-override",
    profile: ApplicationServiceVirtualHIDProfileStatus? = nil
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      runtimeIdentifier: runtimeIdentifier
    )
    device.virtualHIDProfile = profile
    return device
  }

  private static func status(
    _ devices: [ApplicationServiceDeviceDescription]
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
  }

  @Test
  func settingAProfileSendsTheControllerSelectorAndRefreshesInventoryOnce() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)

    let requests = await gateway.overrideRequests
    #expect(requests.count == 1)
    #expect(requests.first?.profile == .generic)
    #expect(
      requests.first?.selector
        == RuntimeDeviceSelector(
          vendorID: 0x1234,
          productID: 0x5678,
          runtimeIdentifier: "session-device-override"
        )
    )
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
    #expect(await gateway.statusCallCount == 1)
  }

  @Test
  func automaticResetsTheOverride() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(nil, for: Self.device())

    let requests = await gateway.overrideRequests
    #expect(requests.count == 1)
    #expect(requests.first?.profile == nil)
  }

  @Test
  func serviceFailureIsShownForThatModelAndKeepsItsDetail() async {
    let gateway = GatewayStub(overrideFailure: .activationFailed(detail: "backend timed out"))
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(.xboxOneSBluetooth, for: Self.device())

    let state = viewModel.virtualHIDProfileOverrideStates[Self.model]
    #expect(state?.inFlight == false)
    #expect(state?.failure?.contains("backend timed out") == true)
    let otherModel = RuntimeControllerModel(vendorID: 0x1234, productID: 0x0001)
    #expect(viewModel.virtualHIDProfileOverrideStates[otherModel] == nil)
  }

  @Test
  func storedButUnappliedFailuresReadDifferentlyFromUnstoredOnes() {
    let stored = [
      RuntimePresentation.virtualHIDProfileOverrideFailure(.outputDisabled),
      RuntimePresentation.virtualHIDProfileOverrideFailure(.overrideRejectedByController),
    ]
    let unstored = [
      RuntimePresentation.virtualHIDProfileOverrideFailure(.unknownProfile),
      RuntimePresentation.virtualHIDProfileOverrideFailure(.persistenceFailed),
    ]
    #expect(stored.allSatisfy { $0.contains("is stored") })
    #expect(unstored.allSatisfy { $0.contains("Nothing was stored") })
    #expect(Set(stored + unstored).count == 4)
  }

  @Test
  func aLaterSuccessClearsTheModelFailure() async {
    let gateway = GatewayStub(overrideFailure: .persistenceFailed)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.failure != nil)

    await gateway.setOverrideFailure(nil)
    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)

    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
  }

  @Test
  func gatewayErrorIsShownAsTheModelFailure() async {
    let gateway = GatewayStub()
    await gateway.setOverrideError(.timeout)
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(nil, for: Self.device())

    let state = viewModel.virtualHIDProfileOverrideStates[Self.model]
    #expect(state?.inFlight == false)
    #expect(
      state?.failure == RuntimePresentation.userFacingError(ApplicationServiceClientError.timeout)
    )
  }

  @Test
  func requestStaysInFlightWithItsChoiceAndIgnoresRepeatsUntilItFinishes() async {
    let gateway = GatewayStub()
    await gateway.gateOverrideRequests()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    let request = Task { await viewModel.setVirtualHIDProfileOverride(.generic, for: device) }
    while await gateway.overrideRequests.isEmpty { await Task.yield() }

    let state = viewModel.virtualHIDProfileOverrideStates[Self.model]
    #expect(state?.inFlight == true)
    #expect(state?.request == .set(.generic))
    #expect(state?.request?.requested == .generic)
    await viewModel.setVirtualHIDProfileOverride(nil, for: device)
    #expect(await gateway.overrideRequests.count == 1)

    await gateway.releaseOverrideRequests()
    await request.value

    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
  }

  @Test
  func padsOfTheSameModelShareTheInFlightRequestAndItsFailure() async {
    let gateway = GatewayStub(overrideFailure: .controllerNotFound)
    await gateway.gateOverrideRequests()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let first = Self.device(runtimeIdentifier: "pad-1")
    let second = Self.device(runtimeIdentifier: "pad-2")

    let request = Task { await viewModel.setVirtualHIDProfileOverride(nil, for: first) }
    while await gateway.overrideRequests.isEmpty { await Task.yield() }

    let secondState = viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(second)]
    #expect(secondState?.inFlight == true)
    #expect(secondState?.request == .reset)
    await viewModel.setVirtualHIDProfileOverride(.generic, for: second)
    #expect(await gateway.overrideRequests.count == 1)

    await gateway.releaseOverrideRequests()
    await request.value

    let failure = viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(second)]?.failure
    #expect(failure != nil)
    #expect(
      failure == viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(first)]?.failure
    )
  }

  @Test
  func overrideIssuedDuringAFullRefreshEndsWithFreshStatus() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setStatusReadsAreGated(true)
    let viewModel = RuntimeViewModel(gateway: gateway)

    let refresh = Task { await viewModel.refresh() }
    await gateway.waitForStatusCall(count: 1)
    let request = Task {
      await viewModel.setVirtualHIDProfileOverride(.generic, for: Self.device())
    }
    while await gateway.overrideRequests.isEmpty { await Task.yield() }

    // The full refresh read began before the override and returns the old status.
    await gateway.resumeNextStatusRead()
    await refresh.value
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.inFlight == true)

    await gateway.waitForStatusCall(count: 2)
    let overridden = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: "override",
      override: .generic,
      unavailable: false
    )
    await gateway.setStatusPayload(Self.status([Self.device(profile: overridden)]))
    await gateway.resumeNextStatusRead()
    await request.value

    #expect(await gateway.statusCallCount == 2)
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
    guard case .available(let status) = viewModel.statusState else {
      Issue.record("Expected the refreshed status to be available")
      return
    }
    #expect(status.devices.first?.virtualHIDProfile?.override == .generic)
  }

  @Test
  func failuresOfDisconnectedModelsAreDropped() async {
    let gateway = GatewayStub(
      statusPayload: Self.status([Self.device()]),
      overrideFailure: .serverStopped
    )
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(.generic, for: Self.device())
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.failure != nil)

    await gateway.setStatusPayload(Self.status([]))
    await viewModel.refreshControllerInventory()

    #expect(viewModel.virtualHIDProfileOverrideStates.isEmpty)
  }

  @Test
  func overrideStoreProblemsAppearInTheStatusSummary() {
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [],
        virtualHIDProfileOverrideError: "unsupported-schema"
      )
    )

    let messages = status.virtualHIDProfileOverrideStoreMessages
    #expect(messages.count == 1)
    #expect(messages.first?.contains("unsupported-schema") == true)
  }

  @Test
  func publishedIdentityComesFromTheLiveVirtualHIDProfile() {
    let xbox = Self.device(
      profile: ApplicationServiceVirtualHIDProfileStatus(
        profile: .xboxOneSBluetooth,
        source: "override",
        override: .xboxOneSBluetooth,
        unavailable: false
      )
    )
    #expect(xbox.publishedIdentityLabel.contains("045E:02FD"))
    #expect(xbox.publishedIdentityPresentation.glyphFamily == .xbox)

    let unpublished = Self.device()
    #expect(unpublished.publishedVirtualProfile == nil)
    #expect(unpublished.publishedIdentityLabel == RuntimePresentation.noVirtualHIDProfileLabel)
  }
}
