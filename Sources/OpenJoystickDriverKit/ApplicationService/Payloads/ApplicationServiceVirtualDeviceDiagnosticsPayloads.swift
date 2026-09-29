import Foundation

/// Redacted serial number state for a HID device.
public enum ApplicationServiceSerialKind: String, Codable, Sendable {
  case none
  case ojdUserSpace
  case present
}

/// Safe (non-sensitive) snapshot of a HID "GamePad" device as seen by IOKit.
public struct ApplicationServiceHIDGamepadSnapshot: Codable, Sendable, Hashable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let product: String?
  public let transport: String?
  public let locationID: UInt32?
  public let serialKind: ApplicationServiceSerialKind
  public let ioUserClass: String?

  /// True if this looks like an OJD app-owned virtual HID device.
  public let isOJDUserSpace: Bool
  /// True if Apple's GameController.framework says this HID device gets a GCController.
  public let isGameControllerSupported: Bool?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    product: String?,
    transport: String?,
    locationID: UInt32?,
    serialKind: ApplicationServiceSerialKind,
    ioUserClass: String?,
    isOJDUserSpace: Bool,
    isGameControllerSupported: Bool? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.product = product
    self.transport = transport
    self.locationID = locationID
    self.serialKind = serialKind
    self.ioUserClass = ioUserClass
    self.isOJDUserSpace = isOJDUserSpace
    self.isGameControllerSupported = isGameControllerSupported
  }
}

/// Diagnostics snapshot returned by
/// ``ApplicationServiceClient/getVirtualDeviceDiagnostics()``.
public struct ApplicationServiceVirtualDeviceDiagnosticsPayload: Codable, Sendable {
  public let userSpaceVirtualDeviceEnabled: Bool
  public let userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus
  public let hidGamepads: [ApplicationServiceHIDGamepadSnapshot]

  public init(
    userSpaceVirtualDeviceEnabled: Bool,
    userSpaceVirtualDeviceStatus: VirtualOutputBackendStatus,
    hidGamepads: [ApplicationServiceHIDGamepadSnapshot]
  ) {
    self.userSpaceVirtualDeviceEnabled = userSpaceVirtualDeviceEnabled
    self.userSpaceVirtualDeviceStatus = userSpaceVirtualDeviceStatus
    self.hidGamepads = hidGamepads
  }
}

/// End-to-end verdict for one virtual-device self-test path.
public enum ApplicationServiceVirtualDeviceSelfTestVerdict: String, Codable, Sendable {
  case passed
  case failed
  case inconclusive
}

/// Result of a short "press buttons now" self-test for virtual device input delivery.
public struct ApplicationServiceVirtualDeviceSelfTestPayload: Codable, Sendable {
  public let seconds: Int
  public let userSpaceValueEvents: Int
  public let userSpaceReportEvents: Int
  public let userSpaceRequired: Bool
  public let userSpaceStatus: VirtualOutputBackendStatus

  public var userSpaceVerdict: ApplicationServiceVirtualDeviceSelfTestVerdict {
    guard userSpaceRequired else { return .inconclusive }
    if userSpaceStatus.isError { return .failed }
    if userSpaceValueEvents > 0 || userSpaceReportEvents > 0 { return .passed }
    return .failed
  }

  public var isSuccessful: Bool { userSpaceVerdict == .passed }

  public init(
    seconds: Int,
    userSpaceValueEvents: Int,
    userSpaceReportEvents: Int,
    userSpaceRequired: Bool = true,
    userSpaceStatus: VirtualOutputBackendStatus = .off
  ) {
    self.seconds = seconds
    self.userSpaceValueEvents = userSpaceValueEvents
    self.userSpaceReportEvents = userSpaceReportEvents
    self.userSpaceRequired = userSpaceRequired
    self.userSpaceStatus = userSpaceStatus
  }
}
