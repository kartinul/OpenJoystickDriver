import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

extension PhysicalRumbleOutputTests {
  @Test
  func testDs4ColorReportsUseExactUsbAndBluetoothLayouts() {
    let usb = DualShock4Driver().encoded(.setRGB(red: 12, green: 34, blue: 56)).onlyReport
    #expect(usb.reportID == 0x05)
    #expect(usb.bytes.count == 32)
    #expect(usb.bytes[1] == 0x02)
    #expect(Array(usb.bytes[6...8]) == [12, 34, 56])

    let bluetooth = DualShock4Driver(prefersBluetooth: true).encoded(
      .setRGB(red: 12, green: 34, blue: 56)
    ).onlyReport
    #expect(bluetooth.reportID == 0x11)
    #expect(bluetooth.bytes[1] == 0xC4)
    #expect(bluetooth.bytes[3] == 0x02)
    #expect(Array(bluetooth.bytes[8...10]) == [12, 34, 56])
    #expect(Array(bluetooth.bytes[74...77]) == [0xD7, 0xFA, 0x17, 0x24])
  }

  @Test
  func testDualSenseColorReportsUseExactUsbAndBluetoothLayouts() {
    let usb = DualSenseDriver().encoded(.setRGB(red: 12, green: 34, blue: 56)).onlyReport
    #expect(usb.reportID == 0x02)
    #expect(usb.bytes.count == 63)
    #expect(usb.bytes[2] == 0x04)
    #expect(Array(usb.bytes[45...47]) == [12, 34, 56])

    let bluetooth = DualSenseDriver(prefersBluetooth: true).encoded(
      .setRGB(red: 12, green: 34, blue: 56)
    ).onlyReport
    #expect(bluetooth.reportID == 0x31)
    #expect(bluetooth.bytes[4] == 0x04)
    #expect(Array(bluetooth.bytes[47...49]) == [12, 34, 56])
    #expect(Array(bluetooth.bytes[74...77]) == [0x4C, 0x5A, 0x92, 0x60])
  }

  @Test
  func testDs4PhysicalRumbleReportUsesUSBHIDOutputReport() {
    let report = DualShock4Driver().rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x05)
    #expect(report.bytes.count == 32)
    #expect(report.bytes[0] == 0x05)
    #expect(report.bytes[1] == 0x01)
    #expect(report.bytes[4] == 90)
    #expect(report.bytes[5] == 180)
    #expect(report.bytes.dropFirst(6).allSatisfy { $0 == 0 })
  }

  @Test
  func testDs4PhysicalRumbleReportUsesBluetoothReportAfterBluetoothInput() throws {
    let parser = DualShock4Driver(prefersBluetooth: true)

    let report = parser.rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x11)
    #expect(report.bytes.count == 78)
    #expect(report.bytes[0] == 0x11)
    #expect(report.bytes[1] == 0xC4)
    #expect(report.bytes[3] == 0x01)
    #expect(report.bytes[6] == 90)
    #expect(report.bytes[7] == 180)
    #expect(report.bytes[74...77].contains { $0 != 0 })
  }

  @Test
  func testDs4PreferredBluetoothParserUsesBluetoothPhysicalRumbleBeforeInput() {
    let report = DualShock4Driver(prefersBluetooth: true).rumblePlan(
      left: 180,
      right: 90,
      lt: 255,
      rt: 64
    ).onlyReport

    #expect(report.reportID == 0x11)
    #expect(report.bytes.count == 78)
    #expect(report.bytes[6] == 90)
    #expect(report.bytes[7] == 180)
  }

  func hasPhysicalRumble(_ parser: any PhysicalProtocolDriver) -> Bool {
    let intensities: [PhysicalRumbleMotor: UInt8] = [.leftMain: 1, .leftHaptic: 1]
    return parser.encoded(
      .setRumble(RumbleIntensities(bytes: intensities), duration: .milliseconds(100))
    ) != nil
  }
}
