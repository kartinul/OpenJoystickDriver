import Foundation

/// The key one pending HID initialization runs under.
///
/// A connection of a family with HID protocol roles owns its key, so a sibling interface's
/// arrival never cancels it. Every other connection shares its routing location's key, and a
/// newer connection there replaces the older one.
enum HIDInitializationKey: Hashable {
  case location(UInt32)
  case connection(UUID)
}

extension DeviceManager {
  func hidInitializationKey(for connection: HIDDeviceConnection) -> HIDInitializationKey {
    protocolDriverRegistry.declaresHIDRoles(connection.physicalDevice)
      ? .connection(connection.connectionID) : .location(connection.routingLocationID)
  }

  /// The initialization key of a bound HID controller. A HID key carries an interface number
  /// only for a protocol role.
  func hidInitializationKey(
    for identifier: DeviceIdentifier,
    connectionID: UUID
  ) -> HIDInitializationKey? {
    if identifier.interfaceNumber != nil { return .connection(connectionID) }
    return identifier.locationID.map(HIDInitializationKey.location)
  }

  /// Removes every pending initialization at a routing location except `connectionID`'s and
  /// returns them for the caller to cancel.
  func removeHIDInitializations(
    atLocation locationID: UInt32,
    except connectionID: UUID? = nil
  ) -> [HIDDeviceInitialization] {
    let keys = hidInitializationTasks.filter {
      $0.value.connection.routingLocationID == locationID
        && $0.value.connection.connectionID != connectionID
    }.keys
    return keys.compactMap { hidInitializationTasks.removeValue(forKey: $0) }
  }

  /// The logical-controller key of a HID connection: its location's controller, or one role
  /// keyed with its interface number. Nil without an observed vendor and product ID.
  func hidIdentifier(
    for connection: HIDDeviceConnection,
    role: HIDConnectionRole
  ) -> DeviceIdentifier? {
    let physicalDevice = connection.physicalDevice
    guard let vendorID = physicalDevice.vendorID, let productID = physicalDevice.productID else {
      return nil
    }
    let interfaceNumber: UInt8? = if case .interface(let number) = role { number } else { nil }
    return DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: physicalDevice.serialNumber,
      locationID: connection.routingLocationID,
      interfaceNumber: interfaceNumber
    )
  }

  /// The pipeline that input from one HID connection feeds. A protocol role receives only its
  /// own connection's input. Any other connection feeds its location's controller, as a
  /// location's interfaces did before roles, but never a role: a family's non-role interface
  /// carries no controller input. Only a role's HID key carries an interface number.
  ///
  /// Routing is per connection, but ownership is not: a location's seize, its release to another
  /// client and its reacquisition act on every interface there, so seizing or releasing one
  /// role's interface affects its sibling roles too.
  func hidPipelineKey(forInputFrom connectionID: UUID, locationID: UInt32) -> DeviceIdentifier? {
    if let identifier = hidRoleConnections[connectionID] {
      return deviceInfos[identifier]?.hidConnectionID == connectionID ? identifier : nil
    }
    return pipelines.keys.first { $0.locationID == locationID && $0.interfaceNumber == nil }
  }

  /// Whether a HID controller's output must target its exact connection. A native controller
  /// is never seized, and a protocol role shares its location with sibling interfaces, so the
  /// location path reaches neither.
  func writesExactHIDConnection(_ identifier: DeviceIdentifier, pipeline: DevicePipeline) -> Bool {
    pipeline.observesOnly || identifier.interfaceNumber != nil
  }

  /// The connection a bound HID controller was admitted on.
  func currentHIDConnection(
    for identifier: DeviceIdentifier,
    locationID: UInt32
  ) -> HIDDeviceConnection? {
    guard let info = deviceInfos[identifier], let connectionID = info.hidConnectionID,
      let physicalDevice = info.physicalDevice
    else { return nil }
    return HIDDeviceConnection(
      connectionID: connectionID,
      physicalDevice: physicalDevice,
      routingLocationID: locationID
    )
  }
}
