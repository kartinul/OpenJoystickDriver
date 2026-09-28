import Foundation

extension DualShock4Driver {

  func ds4BluetoothCRC32(report: [UInt8]) -> UInt32 {

    var crc = updateCRC32(0xFFFF_FFFF, byte: ds4BluetoothHIDOutputHeader)
    for byte in report.dropLast(4) { crc = updateCRC32(crc, byte: byte) }
    return ~crc
  }

  func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
    var crc = current ^ UInt32(byte)
    for _ in 0..<8 { if crc & 1 == 1 { crc = (crc >> 1) ^ 0xEDB8_8320 } else { crc >>= 1 } }
    return crc
  }

}
