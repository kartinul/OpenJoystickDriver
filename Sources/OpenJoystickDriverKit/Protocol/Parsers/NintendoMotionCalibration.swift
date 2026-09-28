/// Independent conversion from Nintendo's SPI IMU calibration coefficients into physical units.
struct NintendoMotionCalibration {
  private let gyroOffsets: [Double]
  private let gyroScales: [Double]
  private let accelScales: [Double]
  private var revision: UInt64 = 0
  private let source: ControllerMotionCalibrationSource

  /// `SWITCH_GYRO_SCALE` (14.2842 counts per °/s) and `SWITCH_ACCEL_SCALE` (4096 counts per g) in
  /// SDL `src/joystick/hidapi/SDL_hidapi_switch.c` at SDL `1ce4c5bc`.
  static let nominal = Self(
    gyroOffsets: [0, 0, 0],
    gyroScales: Array(repeating: 1 / 14.2842, count: 3),
    accelScales: Array(repeating: 1 / 4096, count: 3),
    source: .nominalDeviceScale
  )

  /// Scales follow SDL `LoadIMUCalibration` (`SWITCH_GYRO_SCALE_MULT` 936,
  /// `SWITCH_ACCEL_SCALE_MULT` 4) in `src/joystick/hidapi/SDL_hidapi_switch.c` at SDL `1ce4c5bc`.
  static func factory(_ bytes: [UInt8], userOffsets: [UInt8]? = nil) -> Self? {
    guard bytes.count == 24 else { return nil }
    if let userOffsets {
      guard userOffsets.count == 20, userOffsets[0] == 0xB2, userOffsets[1] == 0xA1 else {
        return nil
      }
    }
    func value(_ offset: Int, from data: [UInt8]) -> Double {
      Double(Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)))
    }
    var gyroOffsets: [Double] = []
    var gyroScales: [Double] = []
    var accelScales: [Double] = []
    for axis in 0..<3 {
      let offset = axis * 2
      let gyroOffset =
        userOffsets.map { value(14 + offset, from: $0) } ?? value(12 + offset, from: bytes)
      let accelOffset =
        userOffsets.map { value(2 + offset, from: $0) } ?? value(offset, from: bytes)
      let gyroRange = value(18 + offset, from: bytes) - gyroOffset
      let accelRange = value(6 + offset, from: bytes) - accelOffset
      // Reject erased flash, degenerate ranges, and reversed coefficients atomically.
      guard gyroRange > 0, accelRange > 0 else { return nil }
      gyroOffsets.append(gyroOffset)
      gyroScales.append(936 / gyroRange)
      accelScales.append(4 / accelRange)
    }
    return Self(
      gyroOffsets: gyroOffsets,
      gyroScales: gyroScales,
      accelScales: accelScales,
      source: userOffsets == nil ? .deviceFactory : .factoryWithUserOffsets
    )
  }

  func installed(after previous: Self) -> Self {
    var result = self
    let changed =
      gyroOffsets != previous.gyroOffsets || gyroScales != previous.gyroScales
      || accelScales != previous.accelScales || source != previous.source
    result.revision = previous.revision &+ (changed ? 1 : 0)
    return result
  }

  /// Switch Pro and Joy-Con transform: raw counts, then the SPI factory (or nominal) offset and
  /// scale per axis, then SI, then the raw axes into the canonical frame:
  /// Pro and left Joy-Con (x, y, z) → (-y, x, z); right Joy-Con (x, y, z) → (y, x, -z).
  /// Source: SDL `SendSensorUpdate` in `src/joystick/hidapi/SDL_hidapi_switch.c` at SDL `1ce4c5bc`
  /// maps raw (x, y, z) to its sensor frame (X right, Y up, Z toward the player) as
  /// (-y, z, -x), negating X and Y again for the right Joy-Con. The canonical frame takes SDL's
  /// +Z (toward the player) as -Y and SDL's +Y (up) as +Z. SDL's sideways single-Joy-Con swap is
  /// not applied because OJD has no horizontal Joy-Con layout.
  func sample(
    timestamp: ControllerSampleTimestamp,
    gyro: ControllerRawSensorVector,
    accel: ControllerRawSensorVector,
    layout: NintendoControllerLayout
  ) -> ControllerMotionSample? {
    let rawGyro = [Double(gyro.x), Double(gyro.y), Double(gyro.z)]
    let rawAccel = [Double(accel.x), Double(accel.y), Double(accel.z)]
    let gyroValues = (0..<3).map { (rawGyro[$0] - gyroOffsets[$0]) * gyroScales[$0] }
    // Nintendo's accelerometer offset adjusts sensitivity, not the sampled acceleration.
    let accelValues = (0..<3).map { rawAccel[$0] * accelScales[$0] }
    return ControllerMotionSample(
      timestamp: timestamp,
      canonicalDegreesPerSecond: canonical(gyroValues, layout: layout),
      canonicalG: canonical(accelValues, layout: layout),
      calibrationSource: source,
      calibrationRevision: revision
    )
  }

  private func canonical(
    _ values: [Double],
    layout: NintendoControllerLayout
  ) -> ControllerMotionVector {
    let side = layout == .rightJoyCon ? 1.0 : -1.0
    return ControllerMotionVector(x: values[1] * side, y: values[0], z: -values[2] * side)
  }
}
