import Foundation

@testable import OpenJoystickDriverKit

extension DeviceManager {
  /// Queues a sibling's initialization, then connects a native interface inline at once, as the
  /// detection loop does for back-to-back events.
  func scheduleSiblingThenConnectNative(
    _ sibling: HIDDeviceConnection,
    _ native: HIDDeviceConnection
  ) async {
    scheduleHIDDeviceInitialization(connection: sibling, ownership: .exclusive)
    await handleHIDDeviceConnected(connection: native, ownership: .unknown)
  }
}
