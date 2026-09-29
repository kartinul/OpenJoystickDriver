import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Returns a list of connected device descriptions.
  public func listDevices() async -> [String] {
    await deviceManager.connectedDeviceDescriptions().map {
      Self.deviceDescriptionLine(ApplicationServiceDeviceDescription(snapshot: $0))
    }
  }

  static func deviceDescriptionLine(_ device: ApplicationServiceDeviceDescription) -> String {
    let serialNumber = device.serialNumber == nil ? "none" : "present"
    let quirks = device.quirks.isEmpty ? "none" : device.quirks.joined(separator: ",")
    let backends =
      device.preferredBackends.isEmpty ? "none" : device.preferredBackends.joined(separator: ",")
    let battery = device.connectionState.map { Self.batteryDescription($0.power) } ?? "unknown"
    return "\(device.name) (VID:\(device.vendorID)" + " PID:\(device.productID)"
      + " [\(device.connection)] SN:\(serialNumber))"
      + (device.interfaceNumber.map { " if=\($0)" } ?? "")
      + " protocol=\(device.protocolBinding.rawValue)"
      + " endpoints=in:0x\(String(device.inputEndpoint, radix: 16))"
      + " out:0x\(String(device.outputEndpoint, radix: 16))"
      + " setConfig=\(device.needsSetConfiguration)" + " settleMs=\(device.postHandshakeSettleMs)"
      + " quirks=\(quirks)" + " backends=\(backends)" + " battery=\(battery)"
      + " session=\(device.sessionState.rawValue)"
      + " startup=\(device.startupCommandStatus ?? "not-required")"
  }

  private static func batteryDescription(_ power: ControllerConnectionState.Power) -> String {
    let percentage = power.battery.percentageText ?? "unknown"
    let wired = power.wiredPower.map { $0 ? "yes" : "no" } ?? "unknown"
    return "\(percentage),\(power.charging.rawValue),wired-power-\(wired)"
  }

  /// Returns the current application service status including input monitoring state and
  /// connected devices.
  public func getStatus() async -> Data {
    let permissions = await permissionManager.refreshAccessState()
    let devices = describingVirtualHIDProfiles(
      await deviceManager.connectedDeviceDescriptions().map(
        ApplicationServiceDeviceDescription.init(snapshot:)
      )
    )
    let unboundDevices = await deviceManager.unboundDeviceDescriptions().map(
      ApplicationServiceUnboundDevice.init(snapshot:)
    )
    let passThroughDevices = await deviceManager.passThroughDeviceDescriptions().map(
      ApplicationServicePassThroughDevice.init(snapshot:)
    )
    let userSnapshot = userSpaceStatusSnapshot()
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "\(permissions.inputMonitoring)",
      accessibility: "\(permissions.accessibility)",
      connectedDevices: devices,
      unboundDevices: unboundDevices,
      passThroughDevices: passThroughDevices,
      userSpaceVirtualDeviceEnabled: userSnapshot.enabled,
      userSpaceVirtualDeviceStatus: userSnapshot.status,
      virtualHIDProfileOverrideError: virtualHIDProfileOverrides.loadError?.statusDescription
    )
    do { return try JSONEncoder().encode(payload) } catch {
      print("[ApplicationServiceServer] getStatus encode error: \(error)")
      return Data()
    }
  }

  public func requestRequiredAccess() async -> PermissionManager.Snapshot {
    await permissionManager.requestRequiredAccess()
  }

  public func requestAccess(
    _ requirement: PermissionManager.Requirement
  ) async -> PermissionManager.Snapshot { await permissionManager.requestAccess(requirement) }

  /// Returns the current input state for the specified device as encoded JSON data.
  public func getControllerState(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data? {
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return nil
    }
    let identifier = DeviceIdentifier(vendorID: vendor, productID: product)
    let state = await deviceManager.controllerState(
      for: identifier,
      runtimeIdentifier: runtimeIdentifier
    )
    return try? JSONEncoder().encode(state)
  }

  /// Returns the recent packet log for the specified device as encoded JSON data.
  public func getPacketLog(vendorID: Int, productID: Int, runtimeIdentifier: String?) async -> Data
  {
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return Data()
    }
    let identifier = DeviceIdentifier(vendorID: vendor, productID: product)
    let log = await deviceManager.packetLog(for: identifier, runtimeIdentifier: runtimeIdentifier)
    do { return try JSONEncoder().encode(log) } catch {
      print("[ApplicationServiceServer] getPacketLog encode error: \(error)")
      return Data()
    }
  }

  /// Sends one output command to the selected controller; `ControllerOutputResult` reports what
  /// became of it, including the rumble channels the controller lacks.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) async -> ControllerOutputResult {
    await deviceManager.sendControllerOutput(
      command,
      for: DeviceIdentifier(vendorID: vendorID, productID: productID),
      runtimeIdentifier: runtimeIdentifier
    )
  }

  /// Enables or disables virtual output suppression and reports success.
  public func setSuppressOutput(_ suppress: Bool) async -> Bool {
    do {
      try await remappingRouter.setOutputSuppressed(suppress)
      return true
    } catch { return false }
  }

  public func suspendController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data {
    let result = await deviceManager.suspendController(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID),
      runtimeIdentifier: runtimeIdentifier
    )
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  public func resumeController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data {
    let result = await deviceManager.resumeController(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID),
      runtimeIdentifier: runtimeIdentifier
    )
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  public func disconnectWirelessController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data {
    let result = await deviceManager.disconnectWirelessController(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID),
      runtimeIdentifier: runtimeIdentifier
    )
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  public func getVirtualDeviceDiagnostics() -> Data {
    let userSnapshot = userSpaceStatusSnapshot()
    let payload = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: userSnapshot.enabled,
      userSpaceVirtualDeviceStatus: userSnapshot.status,
      hidGamepads: VirtualDeviceDiagnostics.enumerateHIDGamepads()
    )
    do { return try JSONEncoder().encode(payload) } catch {
      print("[ApplicationServiceServer] getVirtualDeviceDiagnostics encode error: \(error)")
      return Data()
    }
  }

  public func runVirtualDeviceSelfTest(seconds: Int) async -> Data {
    let minimumDiagnosticDurationSeconds = 1
    let maximumDiagnosticDurationSeconds = 30
    let secs = max(minimumDiagnosticDurationSeconds, min(maximumDiagnosticDurationSeconds, seconds))
    let payload = await runVirtualDeviceSelfTestInternal(seconds: secs)
    do { return try JSONEncoder().encode(payload) } catch {
      print("[ApplicationServiceServer] runVirtualDeviceSelfTest encode error: \(error)")
      return Data()
    }
  }

  public func resetSettings() async -> Bool {
    await virtualOutputTransitionCoordinator.enqueue { [weak self] in
      guard let self else { return false }
      return await self.performResetSettingsAsync()
    }
  }

  private func performResetSettingsAsync() async -> Bool {
    resetVirtualHIDProfileSettings()
    let live = await performVirtualOutputBackendActivation()
    let retargeted = await retargetConnectedControllers()
    return live && retargeted
  }
}
