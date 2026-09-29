import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
  private static let probeDelayNanoseconds: UInt64 = 250_000_000

  private final class SelfTestCounter {
    private let counts = Locked((values: 0, reports: 0))

    var userSpaceValueEvents: Int { counts.withLock { $0.values } }
    var userSpaceReportEvents: Int { counts.withLock { $0.reports } }

    enum EventKind {
      case value
      case report
    }

    func record(device: IOHIDDevice, kind: EventKind) {
      // IMPORTANT:
      // IOHIDDevice properties can be incomplete during system-extension replacement/upgrade.
      // Prefer IORegistry properties via IOHIDDeviceGetService for reliable identification.
      func strProp(_ key: String) -> String? {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
          return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        }
        return IOHIDDeviceGetProperty(device, key as CFString) as? String
      }
      func intProp(_ key: String) -> Int {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
          return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int ?? 0
        }
        return IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
      }

      let serial = strProp(kIOHIDSerialNumberKey as String) ?? strProp("SerialNumber")
      let location = intProp(kIOHIDLocationIDKey as String)
      let isUserSpace =
        UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || ((UInt32(truncatingIfNeeded: location) & 0xFFFF_0000)
          == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace)

      guard isUserSpace else { return }
      counts.withLock { counts in
        switch kind {
        case .value: counts.values += 1
        case .report: counts.reports += 1
        }
      }
    }
  }

  func runVirtualDeviceSelfTestInternal(
    seconds: Int
  ) async -> ApplicationServiceVirtualDeviceSelfTestPayload {
    let counter = SelfTestCounter()
    let counterPtr = Unmanaged.passRetained(counter).toOpaque()

    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // IMPORTANT: do not match only "GamePad" usage here.
    //
    // Some installed extension builds (especially during replacement/upgrade or when the app
    // and runtime
    // are temporarily out of sync) may not expose the expected usage keys at the IOHIDManager
    // matching layer. Broad matching keeps the self-test reliable; we filter down to OJD devices
    // in the callback using IOUserClass / serial.
    // Broad matching keeps the self-test reliable; we filter down to OJD devices
    // in the callback using IOUserClass / serial. Exclude Apple GameController
    // synthetics before IOHIDDeviceCreate — match-all hangs on a wedged GamePad-1.
    IOHIDManagerSetDeviceMatching(
      mgr,
      AppleGameControllerSyntheticHID.allHIDDevicesExcludingSynthetics as CFDictionary
    )

    let callback: IOHIDValueCallback = { context, _, sender, _ in
      guard let context else { return }
      let counter = Unmanaged<SelfTestCounter>.fromOpaque(context).takeUnretainedValue()
      if let sender {
        let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        counter.record(device: dev, kind: .value)
      }
    }
    IOHIDManagerRegisterInputValueCallback(mgr, callback, counterPtr)

    let reportCallback: IOHIDReportCallback = { context, _, sender, _, _, _, _ in
      guard let context else { return }
      let counter = Unmanaged<SelfTestCounter>.fromOpaque(context).takeUnretainedValue()
      if let sender {
        let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        counter.record(device: dev, kind: .report)
      }
    }
    IOHIDManagerRegisterInputReportCallback(mgr, reportCallback, counterPtr)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      let code = String(openResult, radix: 16)
      print("[ApplicationServiceServer] Self-test IOHIDManagerOpen warning: \(code)")
    }

    let syntheticIdentifier = await selfTestIdentifier()
    let userSpace = userSpaceLock.withLock { userSpaceDispatcher }
    async let userSpaceExercise: Void = exerciseUserSpaceSelfTest(
      userSpace,
      identifier: syntheticIdentifier
    )
    async let observationWindow: Void = waitForSelfTestWindow(seconds: seconds)
    _ = await (userSpaceExercise, observationWindow)

    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

    let retained = Unmanaged<SelfTestCounter>.fromOpaque(counterPtr).takeRetainedValue()
    return ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: seconds,
      userSpaceValueEvents: retained.userSpaceValueEvents,
      userSpaceReportEvents: retained.userSpaceReportEvents,
      userSpaceRequired: true,
      userSpaceStatus: currentUserSpaceStatus()
    )
  }

  private func selfTestIdentifier() async -> DeviceIdentifier {
    await deviceManager.connectedDeviceIdentifiers().first
      ?? DeviceIdentifier(
        vendorID: 0x4F4A,
        productID: 0x5445,
        serialNumber: "OpenJoystickDriver-SelfTest"
      )
  }

  private func exerciseUserSpaceSelfTest(
    _ userSpace: (any VirtualOutputDispatching)?,
    identifier: DeviceIdentifier
  ) async {
    for probe in 0..<4 {
      await userSpace?.activateOutput(for: identifier)
      if probe < 3 { try? await Task.sleep(nanoseconds: Self.probeDelayNanoseconds) }
    }
  }

  private func waitForSelfTestWindow(seconds: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds) * Self.nanosecondsPerSecond)
  }

}
