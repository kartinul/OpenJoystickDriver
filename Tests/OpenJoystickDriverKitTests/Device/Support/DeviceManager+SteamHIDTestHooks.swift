import Foundation

@testable import OpenJoystickDriverKit

extension DeviceManager {
  /// Schedules each connection's initialization in one actor turn, as back-to-back detection
  /// events do, so none has started when the next is scheduled.
  func scheduleHIDInitializationsForTest(_ connections: [HIDDeviceConnection]) {
    for connection in connections {
      scheduleHIDDeviceInitialization(connection: connection, ownership: .exclusive)
    }
  }
}
