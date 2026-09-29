import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerActionFailureTests {
  private static func device(runtimeIdentifier: String) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "Bluetooth",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  @Test
  func rejectedSuspendStaysVisibleForThatControllerAfterTheRefresh() async {
    // The stub gateway rejects session changes with `notFound`.
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.suspendController(Self.device(runtimeIdentifier: "pad-a"))

    #expect(await gateway.statusCallCount == 1)
    #expect(
      viewModel.controllerActionFailures == [
        "pad-a": RuntimePresentation.userFacingError(
          ApplicationServiceGatewayError.controllerSessionChangeRejected
        )
      ]
    )
  }

  @Test
  func failedWirelessDisconnectShowsTheServiceStageAndCause() async {
    let viewModel = RuntimeViewModel(gateway: GatewayStub())

    await viewModel.disconnectWirelessController(Self.device(runtimeIdentifier: "pad-b"))

    let failure = viewModel.controllerActionFailures["pad-b"]
    #expect(failure?.contains(WirelessControllerDisconnectFailure.notFound.rawValue) == true)
  }

  @Test
  func theNextActionClearsTheControllersPreviousFailure() async {
    let viewModel = RuntimeViewModel(gateway: GatewayStub())
    viewModel.controllerActionFailures = ["pad-c": "earlier", "pad-d": "other"]

    await viewModel.resumeController(Self.device(runtimeIdentifier: "pad-c"))

    #expect(viewModel.controllerActionFailures["pad-c"] != "earlier")
    #expect(viewModel.controllerActionFailures["pad-d"] == "other")
  }
}
