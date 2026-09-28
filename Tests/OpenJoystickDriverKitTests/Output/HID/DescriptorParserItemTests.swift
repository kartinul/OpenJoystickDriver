import Testing

@testable import OpenJoystickDriverKit

struct DescriptorParserItemTests {
  @Test
  func truncatedLongItemIsRejected() {
    // A long item announcing 5 data bytes with only 1 present.
    #expect(HIDReportDescriptorParser.parse(descriptor: [0xFE, 0x05, 0x00, 0x01]) == nil)
    let complete = HIDReportDescriptorParser.parse(descriptor: [0xFE, 0x01, 0x00, 0x01])
    #expect(complete?.containsUnsupportedItem == true)
  }

  @Test
  func featureItemIsRecorded() {
    let feature: [UInt8] = [0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x09, 0x01, 0xB1, 0x02, 0xC0]
    let input: [UInt8] = [0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x09, 0x01, 0x81, 0x02, 0xC0]
    #expect(HIDReportDescriptorParser.parse(descriptor: feature)?.containsFeatureItem == true)
    #expect(HIDReportDescriptorParser.parse(descriptor: input)?.containsFeatureItem == false)
  }
}
