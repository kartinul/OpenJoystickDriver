import Foundation

@testable import OpenJoystickDriverKit

enum HIDTeardownRaceTrigger {
  case accessFailure
  case denied
}

extension DeviceManager {
  func markStartedForTest() { isStarted = true }

  func setStoppingForTest(_ stopping: Bool) { isStopping = stopping }

  func setManualRumbleForTest(on identifier: DeviceIdentifier) {
    _ = physicalOutputOwnership.setManual(.rumble(motor: .leftMain, intensity: 1), for: identifier)
  }

  func holdPermissionWatchForTest() {
    permissionWatchTask = Task { try? await Task.sleep(for: .seconds(3_600)) }
  }

  func installHIDInitializationForTest(_ initialization: HIDDeviceInitialization) {
    hidInitializationTasks[hidInitializationKey(for: initialization.connection)] = initialization
  }

  func installLifecycleTasksForTest(
    permissionWatcher: Task<Void, Never>,
    initialization: HIDDeviceInitialization
  ) {
    permissionWatchTask = permissionWatcher
    hidInitializationTasks[hidInitializationKey(for: initialization.connection)] = initialization
  }

  func outputQueueForTest(for identifier: DeviceIdentifier) -> PhysicalHIDOutputSerialQueue? {
    hidOutputQueues[identifier]
  }

  func installOutputQueueForTest(
    _ queue: PhysicalHIDOutputSerialQueue,
    for identifier: DeviceIdentifier
  ) { hidOutputQueues[identifier] = queue }
}
