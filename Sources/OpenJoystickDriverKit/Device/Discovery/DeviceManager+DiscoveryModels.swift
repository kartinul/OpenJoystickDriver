import Foundation

extension DeviceManager {
  enum DiscoverySource {
    case hid
    case rawUSB(route: USBTransportRoute)

    var requiresInputMonitoring: Bool {
      if case .hid = self { return true }
      return false
    }

    var kind: DeviceDiscoverySource {
      switch self {
      case .hid: .hid
      case .rawUSB: .rawUSB
      }
    }

    var ownershipObservation: ControllerOwnershipObservation {
      switch self {
      case .hid: .nativeHIDVisible
      case .rawUSB(.ioUSBHost): .exclusiveRawUSB
      case .rawUSB(.usbDriverKit): .driverKitOwnedUSB
      }
    }
  }

  struct DeviceInfo {
    let name: String
    let connection: String
    let serialNumber: String?
    let discoverySource: DiscoverySource
    let binding: ProtocolBinding
    var hidInputOwnership: HIDInputOwnership = .unknown
    let physicalDevice: PhysicalDevice?
    let hidConnectionID: UUID?
    /// Exact enumerated service snapshot used for USB route ownership, not descriptor evidence.
    let usbTransportDevice: USBTransportDevice?

    init(
      name: String,
      connection: String,
      serialNumber: String?,
      discoverySource: DiscoverySource,
      binding: ProtocolBinding,
      hidInputOwnership: HIDInputOwnership = .unknown,
      physicalDevice: PhysicalDevice? = nil,
      hidConnectionID: UUID? = nil,
      usbTransportDevice: USBTransportDevice? = nil
    ) {
      self.name = name
      self.connection = connection
      self.serialNumber = serialNumber
      self.discoverySource = discoverySource
      self.binding = binding
      self.hidInputOwnership = hidInputOwnership
      self.physicalDevice = physicalDevice
      self.hidConnectionID = hidConnectionID
      self.usbTransportDevice = usbTransportDevice
    }

    var ownershipObservation: ControllerOwnershipObservation {
      if physicalDevice?.nativePassThrough == true { return .nativeGamepad }
      if case .hid = discoverySource, hidInputOwnership == .exclusive { return .exclusiveHID }
      return discoverySource.ownershipObservation
    }
  }
}
