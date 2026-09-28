import Testing

@testable import OpenJoystickDriverKit

extension [PhysicalOutputWrite] {
  /// The USB packets these writes send, in order.
  var usbPackets: [PhysicalUSBOutputPacket] {
    compactMap { write in
      guard case .usb(let packet, _) = write else { return nil }
      return packet
    }
  }

  /// The bytes these writes send, in order.
  var usbBytes: [[UInt8]] { usbPackets.map(\.bytes) }

  /// The HID output reports these writes send, in order.
  var hidOutputs: [PhysicalHIDOutputReport] {
    compactMap { write in
      guard case .hidOutput(let report) = write else { return nil }
      return report
    }
  }

  /// The HID feature reports these writes send, in order.
  var hidFeatures: [PhysicalHIDOutputReport] {
    compactMap { write in
      guard case .hidFeature(let report) = write else { return nil }
      return report
    }
  }
}

extension RumbleIntensities {
  /// Intensities from protocol bytes; a motor absent from `bytes` is off.
  init(bytes: [PhysicalRumbleMotor: UInt8]) {
    self = .off
    for (motor, byte) in bytes { self[motor] = UnipolarValue(byte: byte) }
  }
}

extension PhysicalProtocolDriver {
  /// The plan for `command`; nil when the driver throws.
  func encoded(_ command: ControllerOutputCommand) -> PhysicalOutputPlan? { try? encode(command) }

  /// A 0 ms rumble for the main and trigger motors.
  func rumblePlan(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8) -> PhysicalOutputPlan? {
    let intensities: [PhysicalRumbleMotor: UInt8] = [
      .leftMain: left, .rightMain: right, .leftTrigger: lt, .rightTrigger: rt,
    ]
    return encoded(.setRumble(RumbleIntensities(bytes: intensities), duration: .milliseconds(0)))
  }
}

extension PhysicalOutputPlan? {
  /// The plan's only HID output or feature report; records an issue when there is not exactly one.
  var onlyReport: PhysicalHIDOutputReport {
    let reports = (self?.writes.hidOutputs ?? []) + (self?.writes.hidFeatures ?? [])
    guard reports.count == 1, self?.writes.count == 1 else {
      Issue.record("expected one HID report, got \(String(describing: self))")
      return PhysicalHIDOutputReport(reportID: 0, bytes: [])
    }
    return reports[0]
  }

  /// The plan's only USB packet; records an issue when there is not exactly one.
  var onlyPacket: PhysicalUSBOutputPacket {
    let packets = self?.writes.usbPackets ?? []
    guard packets.count == 1, self?.writes.count == 1 else {
      Issue.record("expected one USB packet, got \(String(describing: self))")
      return PhysicalUSBOutputPacket(endpoint: 0, bytes: [], timeoutMilliseconds: 0)
    }
    return packets[0]
  }
}

extension DeviceManager {
  /// Sends one manual output command and reports whether it was delivered.
  func sendOutputForTest(
    _ command: ControllerOutputCommand,
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil
  ) async -> Bool {
    await sendControllerOutput(command, for: identifier, runtimeIdentifier: runtimeIdentifier)
      .isDelivered
  }

  /// A manual main-and-trigger rumble with the main motors mirrored onto the Steam haptics, as
  /// the CLI, the GUI and consumer feedback send it.
  func sendManualRumble(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) async -> Bool {
    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(byte: left),
      rightMain: UnipolarValue(byte: right),
      leftTrigger: UnipolarValue(byte: lt),
      rightTrigger: UnipolarValue(byte: rt)
    ).mirroringMainOntoHaptics()
    return await sendOutputForTest(
      .setRumble(intensities, duration: .milliseconds(durationMs)),
      for: identifier,
      runtimeIdentifier: runtimeIdentifier
    )
  }
}
