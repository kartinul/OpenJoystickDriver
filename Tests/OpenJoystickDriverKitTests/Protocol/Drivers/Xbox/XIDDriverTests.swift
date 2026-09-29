import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func makeXIDReport(
  digital: UInt8 = 0,
  analogA: UInt8 = 0,
  analogB: UInt8 = 0,
  analogX: UInt8 = 0,
  analogY: UInt8 = 0,
  black: UInt8 = 0,
  white: UInt8 = 0,
  lt: UInt8 = 0,
  rt: UInt8 = 0,
  lsx: Int16 = 0,
  lsy: Int16 = 0
) -> Data {
  var r = [UInt8](repeating: 0, count: 20)
  r[0] = 0x00
  r[1] = 0x14
  r[2] = digital
  r[4] = analogA
  r[5] = analogB
  r[6] = analogX
  r[7] = analogY
  r[8] = black
  r[9] = white
  r[10] = lt
  r[11] = rt
  let lsxBits = UInt16(bitPattern: lsx)
  r[12] = UInt8(lsxBits & 0xFF)
  r[13] = UInt8(lsxBits >> 8)
  let lsyBits = UInt16(bitPattern: lsy)
  r[14] = UInt8(lsyBits & 0xFF)
  r[15] = UInt8(lsyBits >> 8)
  return Data(r)
}

struct XIDDriverTests {
  @Test
  func rumbleUsesXIDBigEndianFullRangeMotorsAndCatalogEndpoint() throws {
    let parser = XIDDriver(outEndpoint: 0x07)
    let catalogParser = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x045E, productID: 0x0202)) as? XIDDriver
    )

    #expect(parser.outputCapabilities.rumbleMotors == [.leftMain, .rightMain])
    #expect(parser.outputCapabilities.supportsRumble)
    #expect(catalogParser.rumblePlan(left: 0, right: 0, lt: 0, rt: 0).onlyPacket.endpoint == 0x02)
    #expect(
      parser.rumblePlan(left: 0, right: 0, lt: 255, rt: 255).onlyPacket
        == PhysicalUSBOutputPacket(
          endpoint: 0x07,
          bytes: [0x00, 0x06, 0x00, 0x00, 0x00, 0x00],
          timeoutMilliseconds: 2_000
        )
    )
    #expect(
      parser.rumblePlan(left: 0x12, right: 0x34, lt: 0, rt: 0).onlyPacket.bytes == [
        0x00, 0x06, 0x12, 0x12, 0x34, 0x34,
      ]
    )
    #expect(
      parser.rumblePlan(left: 255, right: 255, lt: 0, rt: 0).onlyPacket.bytes == [
        0x00, 0x06, 0xFF, 0xFF, 0xFF, 0xFF,
      ]
    )
  }

  @Test(arguments: UInt8(0)...UInt8(15))
  func allDpadMasks(mask: UInt8) throws {
    let directions: [HatDirection] = [
      .neutral, .north, .south, .neutral, .west, .northWest, .southWest, .neutral, .east,
      .northEast, .southEast, .neutral, .neutral, .neutral, .neutral, .neutral,
    ]
    let parser = XIDDriver()
    _ = try parser.parseReport(makeXIDReport(digital: mask == 1 ? 2 : 1))
    let events = try parser.parseReport(makeXIDReport(digital: mask))
    #expect(events?.state.hat == directions[Int(mask)])
  }

  @Test
  func shortReportIsIgnored() throws {
    #expect(try XIDDriver().parseReport(Data([0x00, 0x14, 0x00])) == nil)
  }

  @Test
  func analogABecomesDigitalPress() throws {
    let parser = XIDDriver()
    _ = try parser.parseReport(makeXIDReport())
    let events = try parser.parseReport(makeXIDReport(analogA: 0xFF))
    #expect(events.contains(.press(.faceSouth)))
  }

  @Test
  func digitalStartAndDpadMatchLinuxXpad() throws {
    let parser = XIDDriver()
    _ = try parser.parseReport(makeXIDReport())
    let events = try parser.parseReport(makeXIDReport(digital: 0x11))
    #expect(events.contains(.press(.menu)))
    #expect(events.contains(.hat(.north)))
  }

  @Test
  func analogTriggersAndBlackWhiteShoulders() throws {
    let parser = XIDDriver()
    _ = try parser.parseReport(makeXIDReport())
    let events = try parser.parseReport(makeXIDReport(black: 0x80, white: 0x40, lt: 128, rt: 255))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.rightShoulder)))
    #expect(events.contains(.leftTrigger(128.0 / 255.0)))
    #expect(events.contains(.rightTrigger(1)))
  }

  @Test
  func analogZeroReleasesFaceButton() throws {
    let parser = XIDDriver()
    _ = try parser.parseReport(makeXIDReport(analogY: 0x20))
    let events = try parser.parseReport(makeXIDReport(analogY: 0))
    #expect(events.contains(.release(.faceNorth)))
  }
}
