import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct StatusMappingTests {
  @Test
  func mapsPermissionStatesWithoutTreatingUnknownAsDenied() {
    let snapshot = RuntimeStatusSnapshot(
      payload: payload(inputMonitoring: "denied", accessibility: "unknown")
    )

    #expect(snapshot.permissions.inputMonitoring == .denied)
    #expect(snapshot.permissions.accessibility == .unknown)
    #expect(!snapshot.permissions.isReady)
    #expect(snapshot.permissions.isAvailable)
  }

  @Test
  func marksPermissionStateUnavailableWithoutRuntimeOrLocalEvidence() {
    let snapshot = RuntimeStatusSnapshot.unavailable

    #expect(snapshot.permissions.inputMonitoring == .unavailable)
    #expect(snapshot.permissions.accessibility == .unavailable)
    #expect(!snapshot.permissions.isAvailable)
  }

  @Test
  func mapsOutputErrorSeparatelyFromItsDiagnostic() {
    let snapshot = RuntimeStatusSnapshot(
      payload: payload(enabled: false, outputStatus: "error: Accessibility denied")
    )

    #expect(snapshot.output.state == .error)
    #expect(snapshot.output.diagnostic == "Accessibility denied")
    #expect(snapshot.output.detail == nil)
  }

  @Test
  func distinguishesEnabledDisabledAndUnavailableOutput() {
    #expect(CompatibilityOutputStatus(enabled: true, status: "on").state == .enabled)
    #expect(CompatibilityOutputStatus(enabled: false, status: "off").state == .disabled)
    #expect(CompatibilityOutputStatus(enabled: nil, status: nil).state == .unavailable)
    #expect(CompatibilityOutputStatus(enabled: false, status: "unknown").state == .unavailable)
  }

  @Test
  func wrapsControllerDescriptionsWithoutSynthesizingContractIdentity() {
    let description = ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil
    )
    let snapshot = RuntimeStatusSnapshot(payload: payload(devices: [description]))

    #expect(snapshot.controllers.isAvailable)
    #expect(snapshot.controllers.count == 1)
    #expect(snapshot.controllers.descriptions.first?.name == "Test Controller")
    #expect(snapshot.controllers.descriptions.first?.serialNumber == nil)
  }

  @Test
  func listsDevicesLeftToMacOSInTheStatusText() {
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      passThroughDevices: [
        ApplicationServicePassThroughDevice(vendorID: 0x054C, productID: 0x09CC, connection: "USB")
      ]
    )

    let lines = RuntimeStatusText.payloadLines(RuntimeStatusSnapshot(payload: payload))

    #expect(lines.suffix(2) == ["Left to macOS (1):", "  VID:1356 PID:2508 [USB]"])
  }

  @Test
  func marksANativeGamepadInItsDeviceBlock() throws {
    let native = ApplicationServiceDeviceDescription(
      name: "DUALSHOCK 4",
      vendorID: 0x054C,
      productID: 0x09CC,
      protocolBinding: ProtocolBindingID(.sonyDualShock4, variant: .bluetoothClassic),
      connection: "Bluetooth",
      physicalOwnership: .nativeGamepad,
      serialNumber: nil
    )
    let bound = ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      physicalOwnership: .exclusiveHID,
      serialNumber: nil
    )

    let lines = RuntimeStatusText.payloadLines(
      RuntimeStatusSnapshot(payload: payload(devices: [native, bound]))
    )

    #expect(lines.filter { $0 == "    native=macos virtual=none" }.count == 1)
    let marker = try #require(lines.firstIndex(of: "    native=macos virtual=none"))
    let boundHeader = try #require(lines.firstIndex { $0.hasPrefix("  Test Controller") })
    #expect(marker < boundHeader)
  }

  @Test
  func reportsVirtualProfilesAndOverrideDiagnosticsInsteadOfTheRetiredIdentity() {
    var overridden = ApplicationServiceDeviceDescription(
      name: "Overridden",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil
    )
    overridden.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: "automatic-after-rejecting",
      override: .xboxOneSBluetooth,
      unavailable: false
    )
    var automatic = overridden
    automatic.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .xboxOneSBluetooth,
      source: "automatic",
      override: nil,
      unavailable: false
    )
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [overridden, automatic],
      virtualHIDProfileOverrideError: "unsupported-schema",
      legacyCompatibilityIdentityRejected: "sdl2-3"
    )

    let lines = RuntimeStatusText.payloadLines(RuntimeStatusSnapshot(payload: payload))

    #expect(!lines.contains { $0.contains("identity  :") })
    #expect(lines.contains("  override error: unsupported-schema"))
    #expect(lines.contains("  legacy identity rejected: sdl2-3"))
    #expect(
      lines.filter { $0.hasPrefix("    virtual: ") || $0.hasPrefix("    override: ") } == [
        "    virtual: hid-generic (automatic-after-rejecting)", "    override: hid-xbox-one-s-bt",
        "    virtual: hid-xbox-one-s-bt (automatic)",
      ]
    )
  }

  private func payload(
    inputMonitoring: String = "granted",
    accessibility: String = "granted",
    devices: [ApplicationServiceDeviceDescription] = [],
    enabled: Bool? = true,
    outputStatus: String? = "on"
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputMonitoring: inputMonitoring,
      accessibility: accessibility,
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: enabled,
      userSpaceVirtualDeviceStatus: outputStatus
    )
  }
}
