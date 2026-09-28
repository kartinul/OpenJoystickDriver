@testable import OpenJoystickDriverKit

extension ControllerMotionSample {
  /// Builds a sample from remapping-engine values (degrees per second and g; X right, Y up,
  /// Z toward the player) with the producers' forward conversion into SI and the canonical frame.
  static func engineSpace(
    timestamp: ControllerSampleTimestamp,
    gyroDegreesPerSecond gyro: ControllerMotionVector,
    accelerationG accel: ControllerMotionVector,
    calibrationSource: ControllerMotionCalibrationSource = .nominalDeviceScale,
    calibrationRevision: UInt64 = 0
  ) -> ControllerMotionSample {
    let radians = Double.pi / 180
    let gravity = 9.80665
    guard
      let sample = ControllerMotionSample(
        timestamp: timestamp,
        acceleration: ControllerMotionVector(
          x: accel.x * gravity,
          y: -accel.z * gravity,
          z: accel.y * gravity
        ),
        angularVelocity: ControllerMotionVector(
          x: gyro.x * radians,
          y: -gyro.z * radians,
          z: gyro.y * radians
        ),
        calibrationSource: calibrationSource,
        calibrationRevision: calibrationRevision
      )
    else { preconditionFailure("Test motion must be finite") }
    return sample
  }
}

/// Motion values in tests are compared within a tolerance far below one sensor count.
func isClose(
  _ actual: ControllerMotionVector,
  _ expected: ControllerMotionVector,
  tolerance: Double = 1e-9
) -> Bool {
  abs(actual.x - expected.x) <= tolerance && abs(actual.y - expected.y) <= tolerance
    && abs(actual.z - expected.z) <= tolerance
}

/// Scales a canonical-axis vector given in degrees per second to radians per second.
func radiansPerSecond(_ x: Double, _ y: Double, _ z: Double) -> ControllerMotionVector {
  let scale = ControllerMotionUnits.radiansPerDegree
  return ControllerMotionVector(x: x * scale, y: y * scale, z: z * scale)
}

/// Scales a canonical-axis vector given in standard gravities to metres per second squared.
func metresPerSecondSquared(_ x: Double, _ y: Double, _ z: Double) -> ControllerMotionVector {
  let scale = ControllerMotionUnits.standardGravity
  return ControllerMotionVector(x: x * scale, y: y * scale, z: z * scale)
}
