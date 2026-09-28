import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct StreamConstructionTests {
  /// Constructing a stream must not enumerate attached devices. Each enumerated device loads the
  /// IOHID plug-in, and parallel tests that build many `DeviceManager`s crashed in CoreFoundation's
  /// plug-in teardown when those devices were released. On a host without a matching device the
  /// check passes either way.
  @Test
  func constructionDoesNotEnumerateDevices() {
    let stream = HIDDeviceStream()
    #expect(IOHIDManagerCopyDevices(stream.manager) == nil)
  }

  /// Matching is deferred, not dropped: the first `deviceEvents()` applies it, or the stream would
  /// never see a controller. Holds on a host without a matching device.
  @Test
  @MainActor
  func firstDeviceEventsAppliesMatching() {
    let stream = HIDDeviceStream()
    let events = stream.deviceEvents()
    // Unschedules the manager and finishes the stream, so no callbacks outlive the test.
    defer { stream.cleanup() }
    withExtendedLifetime(events) { #expect(stream.deviceMatchingApplied) }
  }
}
