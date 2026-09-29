public enum RemappingMotionCalibrationCommand: String, Codable, Sendable {
  case start, pause, reset
}

public struct RemappingMotionCalibrationStatus: Codable, Equatable, Sendable {
  public let hasMotionBaseline: Bool
  public let isCollecting: Bool
  public let offsetDegreesPerSecond: ControllerMotionVector
}

public enum RemappingMotionCalibrationError: Error, Equatable, Sendable {
  case controllerUnavailable
  case motionUnavailable
}

extension RemappingEngineState {
  func motionCalibrationStatus(
    for identifier: DeviceIdentifier
  ) -> RemappingMotionCalibrationStatus? {
    guard let motion = devices[identifier]?.motion else { return nil }
    return RemappingMotionCalibrationStatus(
      hasMotionBaseline: motion.motion.latest != nil,
      isCollecting: motion.motion.isManuallyCalibrating,
      offsetDegreesPerSecond: motion.motion.calibrationOffset
    )
  }

  mutating func calibrateMotion(
    _ command: RemappingMotionCalibrationCommand,
    for identifier: DeviceIdentifier
  ) throws -> RemappingMotionCalibrationStatus {
    guard var device = devices[identifier] else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    switch command {
    case .start:
      guard device.motion.motion.startCalibration() else {
        throw RemappingMotionCalibrationError.motionUnavailable
      }
    case .pause: device.motion.motion.pauseCalibration()
    case .reset: device.motion.motion.resetCalibration()
    }
    devices[identifier] = device
    return RemappingMotionCalibrationStatus(
      hasMotionBaseline: device.motion.motion.latest != nil,
      isCollecting: device.motion.motion.isManuallyCalibrating,
      offsetDegreesPerSecond: device.motion.motion.calibrationOffset
    )
  }
}
