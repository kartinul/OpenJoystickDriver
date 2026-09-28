import OpenJoystickDriverKit

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
