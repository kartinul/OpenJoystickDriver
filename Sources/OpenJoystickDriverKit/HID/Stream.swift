import Foundation
import IOKit
import IOKit.hid

/// Watches for HID-class game controllers using Apple's IOKit HID framework.
///
/// Creates an `AsyncStream` of device connect, disconnect, and input report
/// events. IOKit delivers callbacks on the main run loop, and this class
/// forwards them into the stream for safe async consumption.
public final class HIDDeviceStream: @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All IOKit callbacks are scheduled on the main run loop
  // - `deviceEvents()` and `cleanup()` run on main, so `continuation`, `streamGeneration`, device
  //   admission, and report-buffer lifetime are confined to the main thread
  // - `seizeLock` guards the device maps, which output paths also read off main
  // - `deviceEvents()` terminates any existing stream before creating a new one

  let manager: IOHIDManager
  var continuation: AsyncStream<HIDDeviceEvent>.Continuation?
  var streamGeneration = 0
  let seizeLock = NSLock()
  var seizedByLocation: [UInt32: [IOHIDDevice]] = [:]
  var releasedByLocation: [UInt32: [IOHIDDevice]] = [:]
  var connectionsByDeviceID: [UInt64: HIDDeviceConnection] = [:]
  /// Admitted devices this stream opened for shared input, with their input report buffers.
  var sharedOpenByDeviceID: [UInt64: SharedOpenDevice] = [:]
  let eventAdapter = SynchronizedPhysicalHIDBackendEventAdapter()
  /// Models whose family declares HID protocol roles; each of their devices disconnects on its
  /// own removal instead of when its location empties.
  let roleModels: Set<PhysicalHIDIdentity>
  /// Applied by the first `deviceEvents()`, not at init: setting matching makes IOKit create a
  /// device object, and load its plug-in, for every attached match. Main-confined.
  let deviceMatching: CFArray
  var deviceMatchingApplied = false

  /// Creates a new stream that matches HID gamepad devices.
  ///
  /// - Parameter virtualProfile: The virtual device profile to exclude from detection.
  public init(
    virtualProfile _: VirtualDeviceProfile = .default,
    additionalProfileIdentifiers: [DeviceIdentifier] = [],
    roleProfileIdentifiers: [DeviceIdentifier] = []
  ) {
    roleModels = Set(
      roleProfileIdentifiers.compactMap {
        PhysicalHIDIdentity(
          vendorID: UInt64($0.controllerIdentity.vendorID),
          productID: UInt64($0.controllerIdentity.productID)
        )
      }
    )
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var matches: [[String: Any]] = [
      [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
      ]
    ]
    matches += additionalProfileIdentifiers.map {
      [
        kIOHIDVendorIDKey: Int($0.controllerIdentity.vendorID),
        kIOHIDProductIDKey: Int($0.controllerIdentity.productID),
      ]
    }
    deviceMatching =
      matches.map { AppleGameControllerSyntheticHID.ioHIDMatchingExcludingSynthetics($0) }
      as CFArray
  }

  struct SharedOpenDevice {
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutableBufferPointer<UInt8>
  }

  // MARK: - C-convention callbacks

  static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceAdded(device)
  }

  static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceRemoved(device)
  }

  static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleInputValue(value)
  }

  static let inputReportCallback: IOHIDReportCallback = {
    context,
    _,
    sender,
    _,
    reportID,
    report,
    length in
    guard let context, let sender else { return }
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    let loc = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
    let stream = Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue()
    stream.handleInputReport(
      deviceID: stream.trackingID(for: device),
      locationID: UInt32(truncatingIfNeeded: loc),
      reportID: UInt8(truncatingIfNeeded: reportID),
      report: report,
      reportLength: length
    )
  }
}
