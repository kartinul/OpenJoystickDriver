import Foundation
import Testing

@testable import OpenJoystickDriverKit

func makeDS4Report(

  includesReportID: Bool = true,
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  sensorTimestamp: UInt16 = 0,
  status: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: includesReportID ? 64 : 63)

  let base = includesReportID ? 1 : 0
  if includesReportID { report[0] = 0x01 }
  report[base + 0] = leftStickX
  report[base + 1] = leftStickY
  report[base + 2] = rightStickX
  report[base + 3] = rightStickY
  report[base + 4] = buttons0
  report[base + 5] = buttons1
  report[base + 6] = buttons2
  report[base + 7] = leftTrigger
  report[base + 8] = rightTrigger
  report[base + 9] = UInt8(truncatingIfNeeded: sensorTimestamp)
  report[base + 10] = UInt8(truncatingIfNeeded: sensorTimestamp >> 8)
  report[base + 29] = status
  return Data(report)
}

func makeDS4BluetoothReport(
  includesHIDTransaction: Bool = false,
  includesReportID: Bool = true,
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  sensorTimestamp: UInt16 = 0,
  status: UInt8 = 0
) -> Data {
  var report: [UInt8] = []
  if includesHIDTransaction { report.append(0xA1) }
  if includesReportID { report.append(0x11) }
  report.append(contentsOf: [0xC0, 0x00])
  report.append(contentsOf: [
    leftStickX, leftStickY, rightStickX, rightStickY, buttons0, buttons1, buttons2, leftTrigger,
    rightTrigger, UInt8(truncatingIfNeeded: sensorTimestamp),
    UInt8(truncatingIfNeeded: sensorTimestamp >> 8),
  ])
  report.append(contentsOf: [UInt8](repeating: 0, count: 60))
  let commonOffset = (includesHIDTransaction ? 1 : 0) + (includesReportID ? 1 : 0) + 2
  report[commonOffset + 29] = status
  report.append(contentsOf: [0, 0, 0, 0])
  let reportStart = includesHIDTransaction ? 1 : 0
  var crc: UInt32 = 0xFFFF_FFFF
  let framedReport =
    (includesReportID ? [] : [UInt8(0x11)]) + Array(report[reportStart..<(report.count - 4)])

  for byte in [UInt8(0xA1)] + framedReport {
    crc ^= UInt32(byte)
    for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB8_8320) }
  }
  crc = ~crc
  for offset in 0..<4 { report[report.count - 4 + offset] = UInt8((crc >> (offset * 8)) & 0xFF) }

  return Data(report)
}

struct DualShock4DriverTests {}

final class CapturingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private(set) var events: [ControllerEvent] = []

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: DeviceIdentifier
  ) { events.append(event) }

  func activateOutput(for _: DeviceIdentifier) {}
}
