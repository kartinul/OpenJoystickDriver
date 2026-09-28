import Dispatch
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

private actor ControllerRecordProbeIsolation {
  private let driver: any PhysicalProtocolDriver
  /// Produced once, so the RECORD line shows the exact writes sent, sequence numbers included.
  private lazy var startupWrites = driver.startupWrites()

  init(driver: sending any PhysicalProtocolDriver) { self.driver = driver }

  func printRecord(plan: ControllerRecordProbePlan, transport: DeviceTransportProfile) {
    renderProbeRecord(plan: plan, startup: startupWrites, transport: transport)
  }

  func sendStartupPackets(session: any USBTransportSession) async throws {
    try await writeProbeStartupPackets(startupWrites, session: session)
  }

  func monitor(
    transport: DeviceTransportProfile,
    session: any USBTransportSession,
    seconds: Int
  ) async throws -> (packets: Int, events: Int, parseErrors: Int) {
    try await monitorProbeInput(
      driver: driver,
      transport: transport,
      session: session,
      seconds: seconds,
      isolation: self
    )
  }
}

func runControllerRecordProbe(recordPath: String, seconds: Int, validateOnly: Bool) -> Never {
  let exitCode = ExitCodeBox()
  let done = DispatchSemaphore(value: 0)

  Task {
    defer { done.signal() }
    do {
      let plan = try ControllerRecordProbePlan(contentsOf: URL(fileURLWithPath: recordPath))
      if validateOnly {
        await ControllerRecordProbeIsolation(driver: plan.makeUnobservedDriver()).printRecord(
          plan: plan,
          transport: plan.transportProfile
        )
        print("RECORD_VALIDATION result=valid")
        return
      }

      let provider = OpenJoystickDriverUSBTransportProvider()
      let devices = try await provider.devices().filter {
        $0.vendorID == plan.vendorID && $0.productID == plan.productID
      }
      print("USB_MATCHES count=\(devices.count)")
      guard let device = devices.first else {
        fputs("ERROR: no raw USB transport matches the record VID/PID\n", stderr)
        exitCode.value = 2
        return
      }

      print("USB_DEVICE service=\(device.serviceID) location=\(device.locationID)")
      if let product = device.productName { print("USB_STRING product=\(product)") }
      // Validate the claimed interface as discovery does, before open can set the configuration.
      let passive = await provider.resolveTransport(for: device, configured: plan.transportProfile)
      guard let claimed = await provider.resolveUSBConfiguration(device, passive: passive),
        claimed.physicalDevice.map({ $0.serviceIdentity == device.serviceIdentity }) ?? true
      else {
        refuseProbeDevice(
          reason: "configuration-unobserved",
          message: "the device's USB configuration descriptor could not be read; try again",
          exitCode: exitCode
        )
        return
      }
      let driver: any PhysicalProtocolDriver
      switch plan.makeDriver(for: device, claimed: claimed) {
      case .success(let validated): driver = validated
      case .failure(let reason):
        refuseProbeDevice(
          reason: reason.rawValue,
          message: "the device does not satisfy the record's interface contract",
          exitCode: exitCode
        )
        return
      }
      let isolation = ControllerRecordProbeIsolation(driver: driver)
      let transport = claimed.profile
      await isolation.printRecord(plan: plan, transport: transport)
      let session = try await provider.open(
        device,
        options: USBTransportOpenOptions(transportProfile: transport)
      )

      if transport.needsSetConfiguration { print("USB_CONFIGURATION value=1 result=set") }
      if transport.alternateSetting != 0 {
        print(
          "USB_ALTERNATE_SETTING interface=\(transport.interfaceNumber)"
            + " value=\(transport.alternateSetting) result=set"
        )
      }
      print(
        "USB_OPEN interface=\(transport.interfaceNumber)"
          + " route=\(device.route.rawValue) result=opened"
      )

      try await isolation.sendStartupPackets(session: session)
      print("RECORD_HANDSHAKE driver=\(plan.protocolBinding.rawValue) result=complete")

      if transport.postHandshakeSettleNanoseconds > 0 {
        try await Task.sleep(nanoseconds: transport.postHandshakeSettleNanoseconds)
      }
      let summary = try await isolation.monitor(
        transport: transport,
        session: session,
        seconds: seconds
      )
      await session.close()
      print(
        "RECORD_SUMMARY packets=\(summary.packets)"
          + " events=\(summary.events) parse_errors=\(summary.parseErrors)"
      )
      exitCode.value = summary.packets > 0 ? 0 : 3
    } catch {
      fputs("ERROR: record probe failed: \(error.localizedDescription)\n", stderr)
      exitCode.value = 1
    }
  }

  done.wait()
  exit(exitCode.value)
}

/// Refuses a device before any write, when its claimed interface cannot be validated.
private func refuseProbeDevice(reason: String, message: String, exitCode: ExitCodeBox) {
  print("RECORD_BINDING result=refused reason=\(reason)")
  fputs("ERROR: \(message) (\(reason))\n", stderr)
  exitCode.value = 4
}

private func renderProbeRecord(
  plan: ControllerRecordProbePlan,
  startup: [PhysicalOutputWrite],
  transport: DeviceTransportProfile
) {
  let profileStartup = plan.startupPackets.map(\.rawValue).joined(separator: ",")
  let usbStartupBytes = startup.map(\.hexBytes).joined(separator: ",")
  print(
    "RECORD identity=\"\(plan.name)\" vid=\(plan.vendorID) pid=\(plan.productID)"
      + " driver=\(plan.protocolBinding.rawValue)" + " interface=\(transport.interfaceNumber)"
      + " in=\(hex(transport.inputEndpoint))" + " out=\(hex(transport.outputEndpoint))"
      + " configuration=\(transport.needsSetConfiguration ? "set1" : "current")"
      + " profile_startup=\(profileStartup.isEmpty ? "none" : profileStartup)"
      + " usb_startup=\(usbStartupBytes.isEmpty ? "none" : usbStartupBytes)"
  )
}

private func writeProbeStartupPackets(
  _ startup: [PhysicalOutputWrite],
  session: any USBTransportSession
) async throws {
  for write in startup {
    do { try await writeProbe(write, session: session) } catch let error as USBTransportError
      where isIgnorableUSBStartupOutputError(write, error: error)
    {
      print(
        "USB_TX endpoint=\(write.probeEndpoint) result=ignored"
          + " detail=\"\(error)\" bytes=\(write.hexBytes)"
      )
    }
  }
}

/// Writes one driver-produced write and prints it as a USB_TX line.
private func writeProbe(_ write: PhysicalOutputWrite, session: any USBTransportSession) async throws
{
  switch write {
  case .usb(let packet, _):
    _ = try await session.write(
      endpoint: packet.endpoint,
      data: packet.bytes,
      timeout: packet.timeoutMilliseconds
    )
  case .hidOutput, .hidFeature: throw USBTransportError.notSupported
  }
  print("USB_TX endpoint=\(write.probeEndpoint) bytes=\(write.hexBytes)")
}

private func monitorProbeInput(
  driver: any PhysicalProtocolDriver,
  transport: DeviceTransportProfile,
  session: any USBTransportSession,
  seconds: Int,
  isolation: isolated ControllerRecordProbeIsolation
) async throws -> (packets: Int, events: Int, parseErrors: Int) {
  let deadline = Date().addingTimeInterval(TimeInterval(seconds))
  let keepAliveInterval = driver.sessionPlan.usbKeepAliveIntervalNanoseconds
  var lastKeepAlive = DispatchTime.now().uptimeNanoseconds
  var packetCount = 0
  var eventCount = 0
  var parseErrorCount = 0

  while Date() < deadline {
    let now = DispatchTime.now().uptimeNanoseconds
    if let keepAliveInterval, now &- lastKeepAlive >= keepAliveInterval {
      lastKeepAlive = now
      do {
        for write in driver.keepAliveWrites() {
          switch write {
          case .usb(let packet, _):
            _ = try await session.write(
              endpoint: packet.endpoint,
              data: packet.bytes,
              timeout: packet.timeoutMilliseconds
            )
          case .hidOutput, .hidFeature: throw USBTransportError.notSupported
          }
          print("USB_KEEPALIVE result=sent")
        }
      } catch { print("USB_KEEPALIVE result=error detail=\(error.localizedDescription)") }
    }

    do {
      let bytes = try await session.read(
        endpoint: transport.inputEndpoint,
        length: 64,
        timeout: 250
      )
      packetCount += 1
      print(
        "USB_RX endpoint=\(hex(transport.inputEndpoint))"
          + " len=\(bytes.count) bytes=\(bytes.hexBytes)"
      )
      do {
        let event = try driver.parse(
          report: Data(bytes),
          receivedAt: MonotonicTimestamp(nanoseconds: DispatchTime.now().uptimeNanoseconds)
        )
        for write in driver.drainPendingWrites() { try await writeProbe(write, session: session) }
        try await sendLifecyclePackets(driver: driver, session: session, isolation: isolation)
        if let event {
          eventCount += 1
          print("EVENT \(String(describing: event.state))")
        }
      } catch {
        parseErrorCount += 1
        print("PARSE_ERROR detail=\(error.localizedDescription)")
      }
      fflush(stdout)
    } catch USBTransportError.timeout { continue }
  }
  return (packetCount, eventCount, parseErrorCount)
}

private func sendLifecyclePackets(
  driver: any PhysicalProtocolDriver,
  session: any USBTransportSession,
  isolation _: isolated ControllerRecordProbeIsolation
) async throws {
  guard let state = driver.consumeInputConnectionStateChange() else { return }
  print("CONTROLLER_CONNECTION state=\(String(describing: state))")
  for write in driver.inputConnectionWrites(for: state) {
    try await writeProbe(write, session: session)
  }
}

private func hex<T: BinaryInteger>(_ value: T) -> String { "0x" + String(value, radix: 16) }

extension [UInt8] {
  var hexBytes: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}

extension PhysicalOutputWrite {
  var probeEndpoint: String {
    switch self {
    case .usb(let packet, _): hex(packet.endpoint)
    case .hidOutput(let report), .hidFeature(let report): "report=\(hex(report.reportID))"
    }
  }

  var hexBytes: String {
    switch self {
    case .usb(let packet, _): packet.bytes.hexBytes
    case .hidOutput(let report), .hidFeature(let report): report.bytes.hexBytes
    }
  }
}
