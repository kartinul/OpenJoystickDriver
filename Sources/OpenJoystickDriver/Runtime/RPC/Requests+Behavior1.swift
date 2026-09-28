import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Returns a list of connected device descriptions.
  public func listDevices(reply: @escaping ([String]) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let devices = await dm.connectedDeviceDescriptions()
      let strings = devices.map(Self.deviceDescriptionLine)
      callback.call(strings)
    }
  }

  static func deviceDescriptionLine(_ device: ApplicationServiceDeviceDescription) -> String {
    let serialNumber = device.serialNumber ?? "none"
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
  public func getStatus(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    let pm = permissionManager
    Task {
      let permissions = await pm.refreshAccessState()
      let devices = describingVirtualHIDProfiles(await dm.connectedDeviceDescriptions())
      let unboundDevices = await dm.unboundDeviceDescriptions()
      let passThroughDevices = await dm.passThroughDeviceDescriptions()
      let userSnapshot = userSpaceStatusSnapshot()
      let payload = ApplicationServiceStatusPayload(
        inputMonitoring: "\(permissions.inputMonitoring)",
        accessibility: "\(permissions.accessibility)",
        connectedDevices: devices,
        unboundDevices: unboundDevices,
        passThroughDevices: passThroughDevices,
        userSpaceVirtualDeviceEnabled: userSnapshot.enabled,
        userSpaceVirtualDeviceStatus: userSnapshot.status,
        virtualHIDProfileOverrideError: virtualHIDProfileOverrides.loadError?.statusDescription,
        legacyCompatibilityIdentityRejected: virtualHIDProfileOverrides.legacyCompatibilityIdentity
      )
      do {
        let data = try JSONEncoder().encode(payload)
        callback.call(data)
      } catch {
        print("[ApplicationServiceServer] getStatus encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func requestRequiredAccess(reply: @escaping (PermissionManager.Snapshot) -> Void) {
    let callback = SendableReply(call: reply)
    let pm = permissionManager
    Task {
      let snapshot = await pm.requestRequiredAccess()
      callback.call(snapshot)
    }
  }

  public func requestAccess(
    _ requirement: PermissionManager.Requirement,
    reply: @escaping (PermissionManager.Snapshot) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let pm = permissionManager
    Task {
      let snapshot = await pm.requestAccess(requirement)
      callback.call(snapshot)
    }
  }

  /// Returns the current input state for the specified device as encoded JSON data.
  public func getControllerState(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data?) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      callback.call(nil)
      return
    }
    Task {
      let identifier = DeviceIdentifier(vendorID: vendor, productID: product)
      let state = await dm.controllerState(for: identifier, runtimeIdentifier: runtimeIdentifier)
      callback.call(try? JSONEncoder().encode(state))
    }
  }

  /// Returns the recent packet log for the specified device as encoded JSON data.
  public func getPacketLog(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      callback.call(Data())
      return
    }
    Task {
      let identifier = DeviceIdentifier(vendorID: vendor, productID: product)
      let log = await dm.packetLog(for: identifier, runtimeIdentifier: runtimeIdentifier)
      do {
        let data = try JSONEncoder().encode(log)
        callback.call(data)
      } catch {
        print("[ApplicationServiceServer] getPacketLog encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  /// Sends one output command to the selected controller; `ControllerOutputResult` reports what
  /// became of it, including the rumble channels the controller lacks.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?,
    reply: @escaping (ControllerOutputResult) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: vendorID, productID: productID)
      let result = await dm.sendControllerOutput(
        command,
        for: identifier,
        runtimeIdentifier: runtimeIdentifier
      )
      callback.call(result)
    }
  }

  /// Enables or disables virtual output suppression and reports success.
  public func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void) {
    let callback = SendableReply(call: reply)
    Task {
      do {
        try await remappingRouter.setOutputSuppressed(suppress)
        callback.call(true)
      } catch { callback.call(false) }
    }
  }

  public func suspendController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      let result = await deviceManager.suspendController(
        vendorID: UInt16(clamping: vendorID),
        productID: UInt16(clamping: productID),
        runtimeIdentifier: runtimeIdentifier
      )
      callback.call((try? JSONEncoder().encode(result)) ?? Data())
    }
  }

  public func resumeController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      let result = await deviceManager.resumeController(
        vendorID: UInt16(clamping: vendorID),
        productID: UInt16(clamping: productID),
        runtimeIdentifier: runtimeIdentifier
      )
      callback.call((try? JSONEncoder().encode(result)) ?? Data())
    }
  }
}
