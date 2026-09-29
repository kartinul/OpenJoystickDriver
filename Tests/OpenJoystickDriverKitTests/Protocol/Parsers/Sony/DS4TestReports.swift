func applyDS4BluetoothInputCRC(to report: inout [UInt8], includesHIDTransaction: Bool = false) {
  let start = includesHIDTransaction ? 1 : 0
  var crc: UInt32 = 0xFFFF_FFFF
  for byte in [UInt8(0xA1)] + Array(report[start..<(report.count - 4)]) {
    crc ^= UInt32(byte)
    for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB8_8320) }
  }
  crc = ~crc
  for offset in 0..<4 { report[report.count - 4 + offset] = UInt8((crc >> (offset * 8)) & 0xFF) }
}
