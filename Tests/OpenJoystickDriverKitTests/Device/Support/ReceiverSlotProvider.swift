import Foundation
import IOKit

@testable import OpenJoystickDriverKit

/// A catalogued Xbox 360 receiver (045E:0719) with a synthetic 8-interface configuration
/// descriptor: receiver slot triple FF/5D/81 on 0/2/4/6 and another vendor triple on 1/3/5/7. The
/// layout is synthetic; slot interface numbers on macOS have not been captured. Each opened
/// interface gets its own scripted session, and a reopen gets its `reopened` session.
///
/// Opens model the host: an interface exists only once the device is configured (the IOUSBHost
/// provider waits for its service), and SET_CONFIGURATION, sent when
/// ``USBTransportOpenOptions/setsConfiguration(current:)`` says so, terminates every other open
/// interface.
actor ReceiverSlotProvider: USBTransportProvider {
  static let device = USBTransportDevice(
    route: .ioUSBHost,
    serviceID: 70,
    vendorID: 0x045E,
    productID: 0x0719,
    locationID: 71
  )
  static let slotInterfaces: [UInt8] = [0, 2, 4, 6]

  private var listedDevices: [USBTransportDevice] = [device]
  private let isConfigured: Bool
  let sessions: [UInt8: RecoveryUSBSession]
  let reopened: [UInt8: RecoveryUSBSession]
  private(set) var openedOptions: [USBTransportOpenOptions] = []
  /// Interfaces whose open sent SET_CONFIGURATION, in order.
  private(set) var configuringInterfaces: [UInt8] = []
  /// Open interfaces a SET_CONFIGURATION terminated.
  private(set) var terminatedInterfaces: [UInt8] = []
  private var currentConfiguration: UInt8?
  private var openInterfaces: Set<UInt8> = []

  /// `sessions` maps an interface number to the session its first open returns.
  init(
    sessions: [UInt8: RecoveryUSBSession],
    reopened: [UInt8: RecoveryUSBSession] = [:],
    isConfigured: Bool = true
  ) {
    self.sessions = sessions
    self.reopened = reopened
    self.isConfigured = isConfigured
    currentConfiguration = isConfigured ? 1 : nil
  }

  static func identifier(interface: UInt8) -> DeviceIdentifier {
    DeviceIdentifier(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: interface
    )
  }

  func devices() -> [USBTransportDevice] { listedDevices }

  func setDevices(_ devices: [USBTransportDevice]) { listedDevices = devices }

  func physicalDeviceObservation(for device: USBTransportDevice) -> PhysicalDevice? { passive }

  func resolveTransport(
    for device: USBTransportDevice,
    configured profile: DeviceTransportProfile
  ) -> USBTransportResolution { USBTransportResolution(profile: profile, physicalDevice: passive) }

  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) -> PhysicalDevice? { Self.descriptor }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    let interface = options.interfaceNumber
    let isReopen = openedOptions.contains { $0.interfaceNumber == interface }
    openedOptions.append(options)
    if options.setsConfiguration(current: currentConfiguration) {
      configuringInterfaces.append(interface)
      currentConfiguration = options.configurationValue
      terminatedInterfaces += openInterfaces.subtracting([interface]).sorted()
      openInterfaces.removeAll()
    }
    while currentConfiguration == nil { try await Task.sleep(for: .milliseconds(1)) }
    guard let session = isReopen ? reopened[interface] : sessions[interface] else {
      throw USBTransportError.notFound
    }
    openInterfaces.insert(interface)
    return session
  }

  /// Registry facts before configuration carry no interfaces; after it, the descriptor's.
  private var passive: PhysicalDevice {
    isConfigured
      ? Self.descriptor
      : PhysicalDevice(
        serviceIdentity: Self.device.serviceIdentity,
        vendorID: Self.device.vendorID,
        productID: Self.device.productID,
        deviceClass: 0xFF
      )
  }

  private static let descriptor = PhysicalDevice(
    serviceIdentity: device.serviceIdentity,
    vendorID: device.vendorID,
    productID: device.productID,
    deviceClass: 0xFF,
    configurationValue: 1,
    interfaces: (0..<8).map(ReceiverRoleProfileTests.syntheticInterface)
  )
}
