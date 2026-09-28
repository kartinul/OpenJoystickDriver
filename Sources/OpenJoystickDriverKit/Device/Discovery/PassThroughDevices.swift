import Foundation

/// A HID connection left to macOS, with the routing location that identifies its controller.
struct PassThroughHIDDevice: Equatable {
  let routingLocationID: UInt32
  /// True for a native gamepad no driver bound; false for another interface of a native one.
  let nativePassThrough: Bool
  let description: ApplicationServicePassThroughDevice
}

extension DeviceManager {
  /// Observed devices left to macOS, in a stable order: native gamepads no driver bound and the
  /// other interfaces of a native controller.
  public func passThroughDeviceDescriptions() -> [ApplicationServicePassThroughDevice] {
    passThroughDevices.values.map(\.description).sorted {
      ($0.vendorID, $0.productID, $0.connection) < ($1.vendorID, $1.productID, $1.connection)
    }
  }

  /// Whether a native controller holds the routing location, bound or left to macOS. Location 0
  /// identifies no controller.
  func hasNativeHIDDevice(atLocation locationID: UInt32) -> Bool {
    guard locationID != 0 else { return false }
    return passThroughDevices.values.contains {
      $0.nativePassThrough && $0.routingLocationID == locationID
    }
      || deviceInfos.contains { identifier, info in
        identifier.locationID == locationID && info.physicalDevice?.nativePassThrough == true
      }
  }

  /// Gives a native connection its routing location before it binds: cancels a sibling
  /// interface's initialization and tears down any other HID device OJD bound there (a sibling
  /// interface or a stale connection of the same controller), releasing its input claim, so
  /// macOS keeps every other interface of the controller. Location 0 identifies no controller.
  func prepareNativeHIDLocation(_ connection: HIDDeviceConnection) async {
    let locationID = connection.routingLocationID
    guard locationID != 0 else { return }
    let siblingInitializations = removeHIDInitializations(
      atLocation: locationID,
      except: connection.connectionID
    )
    for initialization in siblingInitializations { initialization.task.cancel() }
    // Their orphan cleanup must finish before this connection records its own DeviceInfo, which
    // shares a sibling's identifier. This cannot deadlock: a cancelled path returns at its next
    // cancellation check, and nothing in it waits on a continuation this caller resumes.
    for initialization in siblingInitializations { await initialization.task.value }
    let siblings = deviceInfos.filter { identifier, info in
      guard identifier.locationID == locationID, case .hid = info.discoverySource else {
        return false
      }
      return info.hidConnectionID != connection.connectionID
    }
    guard !siblings.isEmpty else { return }
    // Teardown reconciles rejected siblings' claims; the bound siblings' claim is released here.
    for identifier in siblings.keys { await tearDownHIDDevice(identifier: identifier) }
    _ = await hidManager.releaseInputClaim(locationID: locationID)
  }

  /// Records a HID connection left to macOS. OJD does not bind it, so it gets no pipeline, no
  /// virtual device, and no claim reconciliation.
  func recordPassThroughDevice(
    _ connection: HIDDeviceConnection,
    vendorID: UInt16,
    productID: UInt16
  ) {
    guard !Task.isCancelled, !isStopping else { return }
    passThroughDevices[connection.connectionID] = PassThroughHIDDevice(
      routingLocationID: connection.routingLocationID,
      nativePassThrough: connection.physicalDevice.nativePassThrough,
      description: ApplicationServicePassThroughDevice(
        vendorID: vendorID,
        productID: productID,
        connection: connection.physicalDevice.transportProperty ?? "HID"
      )
    )
    notifyControllerInventoryChanged()
    print(
      "[DeviceManager] HID device left to macOS (native controller):"
        + String(format: " %04x:%04x", vendorID, productID)
    )
  }

  func clearPassThroughDevice(_ connectionID: UUID) {
    guard passThroughDevices.removeValue(forKey: connectionID) != nil else { return }
    notifyControllerInventoryChanged()
  }

  func clearPassThroughDevices() {
    guard !passThroughDevices.isEmpty else { return }
    passThroughDevices.removeAll()
    notifyControllerInventoryChanged()
  }
}
