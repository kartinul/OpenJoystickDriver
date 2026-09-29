import Foundation

@testable import OpenJoystickDriverKit

actor USBDiscoveryRecordingProvider: USBTransportProvider {
  private var currentDevices: [USBTransportDevice]
  private let physicalDevice: PhysicalDevice?
  private(set) var resolutionCount = 0
  private(set) var observationResolutionCount = 0

  init(devices: [USBTransportDevice], physicalDevice: PhysicalDevice? = nil) {
    currentDevices = devices
    self.physicalDevice = physicalDevice
  }

  func devices() -> [USBTransportDevice] { currentDevices }

  func setDevices(_ devices: [USBTransportDevice]) { currentDevices = devices }

  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) -> USBTransportResolution {
    resolutionCount += 1
    if physicalDevice != nil { observationResolutionCount += 1 }
    return USBTransportResolution(profile: configured, physicalDevice: physicalDevice)
  }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession { USBDiscoveryRecordingSession() }
}

final class USBDiscoveryRecordingSession: USBTransportSession, @unchecked Sendable {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) -> Int { data.count }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.disconnected
  }
}
