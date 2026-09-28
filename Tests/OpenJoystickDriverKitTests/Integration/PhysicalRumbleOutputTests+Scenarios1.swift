import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

extension PhysicalRumbleOutputTests {
  @Test
  func testSourceBackedParsersExposeExactOutputCapabilities() {
    let gip = GIPDriver()
    let xbox360 = XUSBDriver()
    let xid = XIDDriver()
    let ds4 = DualShock4Driver()
    let dualSense = DualSenseDriver()
    let ds3 = SixaxisDriver()
    let switchPro = Switch1Driver()
    let steamController = SteamControllerDriver()

    #expect(
      Set(gip.outputCapabilities.rumbleMotors)
        == Set([.leftMain, .rightMain, .leftTrigger, .rightTrigger])
    )
    #expect(Set(xbox360.outputCapabilities.rumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(Set(xid.outputCapabilities.rumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(xbox360.outputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(Set(ds4.outputCapabilities.rumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(Set(dualSense.outputCapabilities.rumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(
      Set(dualSense.outputCapabilities.lightingFeatures)
        == Set([.playerIndicator, .programmableColor])
    )
    #expect(ds4.outputCapabilities.lightingFeatures == [.programmableColor])
    #expect(Set(ds3.outputCapabilities.rumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(ds3.outputCapabilities.binaryRumbleMotors == [.rightMain])
    #expect(ds3.outputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(Set(switchPro.outputCapabilities.rumbleMotors) == Set([.leftMain, .rightMain]))
    #expect(switchPro.outputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(steamController.outputCapabilities.rumbleMotors == [.leftHaptic, .rightHaptic])
    #expect(steamController.outputCapabilities.lightingFeatures == [.programmableBrightness])
    #expect(hasPhysicalRumble(gip))
    #expect(hasPhysicalRumble(xbox360))
    #expect(hasPhysicalRumble(xid))
    #expect(hasPhysicalRumble(ds4))
    #expect(hasPhysicalRumble(dualSense))
    #expect(hasPhysicalRumble(ds3))
    #expect(hasPhysicalRumble(switchPro))
    #expect(hasPhysicalRumble(steamController))
  }

  @Test
  func testServiceDescriptionDefaultsToNoPhysicalOutputCapabilities() {
    let description = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture
    )

    #expect(description.physicalOutputCapabilities == .none)
  }

  @Test
  func testServiceDescriptionRejectsIncompleteOutputCapabilities() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "protocolBinding": "hid.descriptor",
        "connection": "USB",
        "serialNumber": null,
        "bindingResult": {
          "outcome": "bound", "accessBackend": "iohid", "interfaces": [], "rule": "hid-descriptor",
          "matchedPredicates": ["hid-descriptor-contract"], "rejectedCandidates": []
        },
        "runtimeIdentifier": "0001:0002:M"
      }
      """
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: Data(json.utf8))
    }
  }

  @Test
  func testServiceDescriptionRejectsSupportsPhysicalRumbleFlag() throws {
    let json = """
      {
        "name": "Test",
        "vendorID": 1,
        "productID": 2,
        "protocolBinding": "hid.descriptor",
        "connection": "USB",
        "serialNumber": null,
        "bindingResult": {
          "outcome": "bound", "accessBackend": "iohid", "interfaces": [], "rule": "hid-descriptor",
          "matchedPredicates": ["hid-descriptor-contract"], "rejectedCandidates": []
        },
        "runtimeIdentifier": "0001:0002:M",
        "supportsPhysicalRumble": true
      }
      """
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: Data(json.utf8))
    }
  }

  @Test
  func testServiceDescriptionDecodesExactOutputCapabilities() throws {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain, .leftTrigger, .rightTrigger],
      lightingFeatures: [.playerIndicator]
    )
    let original = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: capabilities
    )
    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(original)
    )

    #expect(decoded.physicalOutputCapabilities.supportsRumble)
    #expect(decoded.physicalOutputCapabilities == capabilities)
  }

  @Test
  func testXbox360PlayerIndicatorsMapToSteadyRingPatterns() {
    #expect(XUSBDriver.ledPattern(for: .off) == .allOff)
    #expect(XUSBDriver.ledPattern(for: .player1) == .player1On)
    #expect(XUSBDriver.ledPattern(for: .player2) == .player2On)
    #expect(XUSBDriver.ledPattern(for: .player3) == .player3On)
    #expect(XUSBDriver.ledPattern(for: .player4) == .player4On)
  }

  @Test
  func testConsumerCodecDecodesXboxOneRumbleReportWithCallbackReportIDPrefix() throws {
    let command = try consumerOutput(
      3,
      [0x03, 0x0F, 10, 20, 30, 40, 5, 0, 0],
      in: XboxGeckoHIDReportFormat()
    )

    #expect(
      command
        == .consumerRumble(left: 30, right: 40, leftTrigger: 10, rightTrigger: 20, durationMs: 50)
    )
    // The payload after the report ID is exactly the declared 8 bytes.
    #expect(throws: VirtualHostReportError.tooLarge) {
      try consumerOutput(
        3,
        [0x03, 0x0F, 10, 20, 30, 40, 5, 0, 0, 0],
        in: XboxGeckoHIDReportFormat()
      )
    }
    // The rumble report is numbered; an unnumbered one is not a report the format declares.
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(0, [0x0F, 10, 20, 30, 40, 5, 0, 0], in: XboxGeckoHIDReportFormat())
    }
  }

  @Test
  func testConsumerCodecDecodesXbox360ShortRumbleReports() throws {
    let format = OJDGenericGamepadFormat()
    #expect(
      try consumerOutput(0, [0x08, 0x00, 128, 64], in: format)
        == .consumerRumble(left: 128, right: 64)
    )
    #expect(
      try consumerOutput(0, [0x08, 0x00, 128, 64, 0, 0, 0], in: format)
        == .consumerRumble(left: 128, right: 64)
    )
  }

  @Test
  func testConsumerCodecDecodesOJDCompactRumbleReports() throws {
    let command = try consumerOutput(
      0,
      [0x4F, 1, 2, 3, 4, 0x2C, 0x01],
      in: OJDGenericGamepadFormat()
    )

    let expected = ControllerOutputCommand.consumerRumble(
      left: 1,
      right: 2,
      leftTrigger: 3,
      rightTrigger: 4,
      durationMs: 300
    )
    #expect(command == expected)
  }

  @Test
  func testConsumerCodecRejectsUnmarkedCompactOutputReports() {
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(0, [1, 2, 3, 4, 5, 6], in: OJDGenericGamepadFormat())
    }
  }

  @Test
  func testDs3PhysicalOutputMatchesLinuxDefaultReport() {
    let report = SixaxisDriver().rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x01)
    #expect(report.bytes.count == 49)
    #expect(Array(report.bytes[0...10]) == [0x01, 0x01, 0xFF, 0x01, 0xFF, 180, 0, 0, 0, 0, 0x02])
    #expect(
      Array(report.bytes[11...35]) == [
        0xFF, 0x27, 0x10, 0x00, 0x32, 0xFF, 0x27, 0x10, 0x00, 0x32, 0xFF, 0x27, 0x10, 0x00, 0x32,
        0xFF, 0x27, 0x10, 0x00, 0x32, 0, 0, 0, 0, 0,
      ]
    )
    #expect(report.bytes[36...].allSatisfy { $0 == 0 })
  }

  @Test
  func testDs3SmallMotorIsBinaryAndOutputStatePersistsAcrossLedChanges() {
    let parser = SixaxisDriver()
    let off = parser.rumblePlan(left: 33, right: 0, lt: 0, rt: 0).onlyReport
    #expect(off.bytes[3] == 0)
    let on = parser.rumblePlan(left: 33, right: 1, lt: 0, rt: 0).onlyReport
    #expect(on.bytes[3] == 1)

    let led = parser.encoded(.setPlayerIndicator(.player4)).onlyReport
    #expect(led.bytes[3] == 1)
    #expect(led.bytes[5] == 33)
    #expect(led.bytes[10] == 0x10)
    let allOff = parser.encoded(.setPlayerIndicator(.off)).onlyReport
    #expect(allOff.bytes[10] == 0x20)
  }

  @Test
  func testCapabilitiesRejectBinaryMarkersForUnsupportedMotors() {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain],
      binaryRumbleMotors: [.leftMain, .rightMain]
    )

    #expect(capabilities.binaryRumbleMotors == [.leftMain])
  }

  @Test
  func testDualSensePhysicalRumbleUsesExactUSBOutputLayout() {
    let report = DualSenseDriver().rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x02)
    #expect(report.bytes.count == 63)
    #expect(report.bytes[0] == 0x02)
    #expect(report.bytes[1] == 0x03)
    #expect(report.bytes[3] == 90)
    #expect(report.bytes[4] == 180)
    #expect(report.bytes.dropFirst(5).allSatisfy { $0 == 0 })
  }

  @Test
  func testDualSensePhysicalRumbleUsesSignedBluetoothOutputLayout() {
    let parser = DualSenseDriver(prefersBluetooth: true)
    let report = parser.rumblePlan(left: 180, right: 90, lt: 255, rt: 64).onlyReport

    #expect(report.reportID == 0x31)
    #expect(report.bytes.count == 78)
    #expect(Array(report.bytes[0...6]) == [0x31, 0x00, 0x10, 0x03, 0x00, 90, 180])
    #expect(Array(report.bytes[74...77]) == [0xB9, 0x4F, 0xE2, 0xCD])
    let next = parser.rumblePlan(left: 0, right: 0, lt: 0, rt: 0).onlyReport
    #expect(next.bytes[1] == 0x10)
  }

  @Test
  func testDualSensePlayerIndicatorUsesCenteredLinuxPatterns() {
    let parser = DualSenseDriver()
    let expected: [(PhysicalPlayerIndicator, UInt8)] = [
      (.off, 0x00), (.player1, 0x04), (.player2, 0x0A), (.player3, 0x15), (.player4, 0x1B),
    ]

    for (indicator, pattern) in expected {
      let report = parser.encoded(.setPlayerIndicator(indicator)).onlyReport
      #expect(report.reportID == 0x02)
      #expect(report.bytes.count == 63)
      #expect(report.bytes[2] == 0x10)
      #expect(report.bytes[44] == pattern)
    }
  }

  @Test
  func testDualSenseBluetoothPlayerIndicatorIsSigned() {
    let report = DualSenseDriver(prefersBluetooth: true).encoded(.setPlayerIndicator(.player3))
      .onlyReport

    #expect(report.reportID == 0x31)
    #expect(report.bytes[4] == 0x10)
    #expect(report.bytes[46] == 0x15)
    #expect(Array(report.bytes[74...77]) == [0x7B, 0x4C, 0x1C, 0xA9])
  }

}
