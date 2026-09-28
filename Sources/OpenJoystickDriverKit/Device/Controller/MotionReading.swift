/// A three-axis motion vector. Each property that stores one declares its units and frame.
public struct ControllerMotionVector: Sendable, Equatable, Codable {
  public let x: Double
  public let y: Double
  public let z: Double

  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

public enum ControllerMotionCalibrationSource: String, Sendable, Codable {
  case nominalDeviceScale
  case deviceFactory
  case factoryWithUserOffsets
}

/// Unit factors shared by motion producers and the remapping consumer.
enum ControllerMotionUnits {
  /// `SDL_STANDARD_GRAVITY` (9.80665 m/s²) in SDL `include/SDL3/SDL_sensor.h` at SDL `1ce4c5bc`.
  static let standardGravity = 9.80665
  static let radiansPerDegree = Double.pi / 180
}
