import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct SonyBluetoothCRC32Tests {
  @Test
  func checksumMatchesKnownVectorsAndFixtureReports() {
    // Standard CRC-32 check value: CRC32("123456789"), with "1" as the seed byte.
    #expect(SonyBluetoothCRC32.checksum(seed: 0x31, bytes: Array("23456789".utf8)) == 0xCBF4_3926)

    let input = Array(ProtocolPacketFixtures.DualSense.bluetoothInputReport())
    #expect(
      SonyBluetoothCRC32.checksum(seed: 0xA1, bytes: input.dropLast(4))
        == ProtocolPacketFixtures.DualSense.bluetoothInputCRC32(input)
    )
    #expect(SonyBluetoothCRC32.isValid(seed: 0xA1, report: input))
    #expect(!SonyBluetoothCRC32.isValid(seed: 0xA2, report: input))

    var output = input
    SonyBluetoothCRC32.writeTrailer(seed: 0xA2, report: &output)
    let stored = output.suffix(4).enumerated().reduce(UInt32(0)) { value, element in
      value | (UInt32(element.element) << UInt32(element.offset * 8))
    }
    #expect(stored == ProtocolPacketFixtures.DualSense.bluetoothOutputCRC32(output))
  }
}
