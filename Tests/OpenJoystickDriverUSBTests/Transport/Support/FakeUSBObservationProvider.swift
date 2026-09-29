import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverUSB

actor FakeUSBObservationProvider: USBPhysicalDeviceObservationProvider {
  private let devicesValue: [USBTransportDevice]
  private let observations: [PhysicalDevice]

  init(devices: [USBTransportDevice], observations: [PhysicalDevice]) {
    devicesValue = devices
    self.observations = observations
  }

  func devices() throws -> [USBTransportDevice] { devicesValue }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession { throw USBTransportError.notSupported }

  func physicalDeviceObservations() throws -> [PhysicalDevice] { observations }
}
