import CryptoKit
import Foundation

private enum RuntimeDeviceIdentity {
  /// Ephemeral by construction: this key is generated once per process and is never persisted.
  private static let key = SymmetricKey(size: .bits256)
  private static let tokenLock = NSLock()
  // Guarded by `tokenLock`. Output routing asks for tokens per input report, and each is an HMAC.
  nonisolated(unsafe) private static var tokens: [DeviceIdentifier: String?] = [:]

  static func token(for identifier: DeviceIdentifier) -> String? {
    if let cached = tokenLock.withLock({ tokens[identifier] }) { return cached }
    let token = computeToken(for: identifier)
    tokenLock.withLock { tokens[identifier] = token }
    return token
  }

  private static func computeToken(for identifier: DeviceIdentifier) -> String? {
    let identity = identifier.controllerIdentity
    let model = String(format: "%04X:%04X:", identity.vendorID, identity.productID)
    var components: [String] = []
    if let locationID = identifier.locationID {
      components.append(String(format: "L:%08X", locationID))
    }
    if let serialNumber = identity.serialNumber {
      // Length-prefixed so a serial containing `:` cannot mimic a later component.
      components.append("S:\(serialNumber.utf8.count):" + serialNumber)
    }
    guard !components.isEmpty else { return nil }
    if let interfaceNumber = identifier.interfaceNumber {
      components.append(String(format: "I:%02X", interfaceNumber))
    }
    let preimage = Data((model + components.joined(separator: ":")).utf8)

    let digest = Data(HMAC<SHA256>.authenticationCode(for: preimage, using: key))
    return "E-"
      + digest.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
        of: "/",
        with: "_"
      ).replacingOccurrences(of: "=", with: "")
  }
}

/// The product and physical identity of a controller: vendor ID, product ID and serial number.
///
/// Two identities with the same non-nil serial number name the same physical device, whichever
/// location or interface it is reached through. Without a serial number an identity names only
/// the model, which all controllers of that model share.
public struct ControllerIdentity: Hashable, Sendable {
  /// Vendor ID (VID) - identifies who made the controller (e.g. 0x3537 = Gamesir).
  public let vendorID: UInt16
  /// Product ID (PID) - identifies which model of controller (e.g. 0x1010 = G7 SE).
  public let productID: UInt16
  /// USB serial number reported by the controller.
  ///
  /// Nil if the controller does not provide one; an empty serial is stored as nil.
  public let serialNumber: String?

  /// Creates a new ControllerIdentity.
  public init(vendorID: UInt16, productID: UInt16, serialNumber: String? = nil) {
    self.vendorID = vendorID
    self.productID = productID
    self.serialNumber = serialNumber?.isEmpty == false ? serialNumber : nil
  }

  /// Whether this identity names one physical device rather than every unit of its model.
  public var identifiesPhysicalDevice: Bool { serialNumber != nil }
}

/// Identifies one logical controller for profile matching and multi-controller support.
///
/// The key is the controller's `ControllerIdentity` plus the location and interface it is
/// reached through, so each interface of one physical device keys its own logical controller.
/// The location tells apart controllers whose identity has no serial number; it can change when
/// you unplug and replug.
public struct DeviceIdentifier: Hashable, Sendable {
  /// The product and physical identity this logical controller belongs to.
  public let controllerIdentity: ControllerIdentity
  /// IOKit location ID: the bus number in the high byte, then one port-number nibble per hub
  /// tier (`0x00130000` is bus 0, hub port 1, port 3). HID connections carry their routing
  /// location.
  ///
  /// Stable within a single session but may change after reboot or replug.
  /// Used as a fallback when serial is unavailable.
  public let locationID: UInt32?
  /// USB interface number of the claimed interface, or nil when the key names no interface
  /// (HID and Bluetooth connections).
  public let interfaceNumber: UInt8?

  /// Creates a new DeviceIdentifier from the parts of its `ControllerIdentity`.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String? = nil,
    locationID: UInt32? = nil,
    interfaceNumber: UInt8? = nil
  ) {
    self.controllerIdentity = ControllerIdentity(
      vendorID: vendorID,
      productID: productID,
      serialNumber: serialNumber
    )
    self.locationID = locationID
    self.interfaceNumber = interfaceNumber
  }

  /// Returns true when both identifiers have the same vendor and product ID.
  ///
  /// Regardless of serial number or location. Used for model-level profile matching.
  public func modelMatches(_ other: Self) -> Bool {
    controllerIdentity.vendorID == other.controllerIdentity.vendorID
      && controllerIdentity.productID == other.controllerIdentity.productID
  }

  /// Opaque, session-stable selector used by the local application-service API.
  ///
  /// Exact selectors are authenticated with a process-local, non-persisted key,
  /// making private hardware identity non-reversible and unlinkable across launches.
  /// The model fallback is explicit because it cannot select one of multiple devices.
  public var runtimeIdentifier: String {
    RuntimeDeviceIdentity.token(for: self)
      ?? String(format: "M-%04X-%04X", controllerIdentity.vendorID, controllerIdentity.productID)
  }
}

extension DeviceIdentifier: CustomStringConvertible {
  /// Returns a human-readable representation of the device identifier for logs. It never
  /// includes the serial number, only whether one is present.
  public var description: String {
    let vid = String(format: "0x%04X", controllerIdentity.vendorID)
    let pid = String(format: "0x%04X", controllerIdentity.productID)
    let serial = controllerIdentity.serialNumber == nil ? "" : " serial=present"
    let loc = locationID.map { " loc=\($0)" } ?? ""
    let interface = interfaceNumber.map { " if=\($0)" } ?? ""
    return "DeviceIdentifier(VID:\(vid) PID:\(pid)\(serial)\(loc)\(interface))"
  }
}
