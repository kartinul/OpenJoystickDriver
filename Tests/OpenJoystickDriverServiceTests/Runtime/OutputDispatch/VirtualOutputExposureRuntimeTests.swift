import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

private final class ExposureBackendProbe: VirtualOutputDispatching,
  VirtualOutputControllerActivating, ControllerLifecycleListener, @unchecked Sendable
{
  private(set) var activations: [[DeviceIdentifier]] = []
  private(set) var dispatches = 0
  private(set) var stops = 0
  private(set) var closes = 0
  var suppressOutput = false
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }

  func activate(for identifiers: [DeviceIdentifier]) { activations.append(identifiers) }
  func activate(controller identifier: DeviceIdentifier) { activations.append([identifier]) }
  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {
    dispatches += 1
  }
  func activateOutput(for _: DeviceIdentifier) { dispatches += 1 }
  func controllerDidStop(_: DeviceIdentifier) { stops += 1 }
  func close() { closes += 1 }
}

private final class ExposureState: @unchecked Sendable {
  var ownership: ControllerOwnershipObservation = .exclusiveRawUSB
  var descriptions: [ApplicationServiceDeviceDescription] = []
}

@Suite(.serialized)
struct VirtualOutputExposureRuntimeTests {
  private let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)

  private func gipDescription() -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "GIP",
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      protocolBinding: ProtocolBindingID(.xboxGIP, variant: .usb),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
  }

  @Test
  func automaticSelectedProfileUsesTheSameEligibilityGate() async {
    let state = ExposureState()
    state.descriptions = [gipDescription()]
    let backend = ExposureBackendProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in state.ownership },
      builder: { _ in backend },
      descriptionsProvider: { state.descriptions }
    )

    await dispatcher.activateOutput(for: identifier)
    #expect(backend.dispatches == 1)
    state.ownership = .unknown
    await dispatcher.activateOutput(for: identifier)
    #expect(backend.dispatches == 2)
    await dispatcher.close()
  }
}
