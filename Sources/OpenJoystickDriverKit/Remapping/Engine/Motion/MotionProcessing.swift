/// The engine's motion space: degrees per second and standard gravities in the GamepadMotionHelpers
/// frame (X right, Y up, Z toward the player). Tuning, projections, pointer scales, and manual
/// calibration offsets are expressed in it, so converting here keeps their effective sensitivity.
struct RemappingMotionReading {
  let gyroscopeDegreesPerSecond: ControllerMotionVector
  let accelerationG: ControllerMotionVector
}

extension RemappingMotionReading {
  /// Inverts the producers' SI conversion and maps canonical (x, y, z) to engine (x, z, -y).
  init(_ sample: ControllerMotionSample) {
    let radians = ControllerMotionUnits.radiansPerDegree
    let gravity = ControllerMotionUnits.standardGravity
    let gyro = sample.angularVelocity
    let accel = sample.acceleration
    gyroscopeDegreesPerSecond = ControllerMotionVector(
      x: gyro.x / radians,
      y: gyro.z / radians,
      z: -gyro.y / radians
    )
    accelerationG = ControllerMotionVector(
      x: accel.x / gravity,
      y: accel.z / gravity,
      z: -accel.y / gravity
    )
  }
}

struct RemappingProcessedMotion {
  let timestamp: ControllerSampleTimestamp
  let deltaTime: Double
  let fused: RemappingFusedMotion
  let tunedGyro: RemappingGyroProjection
}

/// Owns one controller's sample clock, runtime bias, and relative orientation.
struct RemappingMotionProcessor {
  private var previous: ControllerSampleTimestamp?
  private var calibrationSource: ControllerMotionCalibrationSource?
  private var calibrationRevision: UInt64?
  private var bias = RemappingMotionBias()
  private var fusion = RemappingMotionFusion()
  private var transform = RemappingMotionTransform()
  private var previousTuning: RemappingMotionTuning?
  private(set) var latest: RemappingProcessedMotion?
  private(set) var isManuallyCalibrating = false

  var calibrationOffset: ControllerMotionVector {
    ControllerMotionVector(x: bias.offset.x, y: bias.offset.y, z: bias.offset.z)
  }

  /// A live baseline is required; discontinuities cancel collection rather than mix sessions.
  @discardableResult
  mutating func startCalibration() -> Bool {
    guard latest != nil else { return false }
    bias.startManualCollection()
    isManuallyCalibrating = true
    return true
  }

  mutating func pauseCalibration() {
    bias.pauseManualCollection()
    isManuallyCalibrating = false
  }

  mutating func resetCalibration() { resetEstimates() }

  @discardableResult
  mutating func process(
    _ sample: ControllerMotionSample,
    tuning: RemappingMotionTuning = .default
  ) -> RemappingProcessedMotion? {
    let timestamp = sample.timestamp
    if let previous {
      guard timestamp.sequenceIndex > previous.sequenceIndex,
        timestamp.monotonic >= previous.monotonic
      else { return nil }
    }
    let reading = RemappingMotionReading(sample)
    guard (try? tuning.validate()) != nil,
      Self.withinBounds(reading.gyroscopeDegreesPerSecond, limit: 1_000_000),
      Self.withinBounds(reading.accelerationG, limit: 1_000)
    else {
      previous = timestamp
      resetEstimates()
      return nil
    }
    let elapsed = previous.map { timestamp.monotonic.nanoseconds - $0.monotonic.nanoseconds } ?? 0
    let discontinuity =
      previous == nil || latest == nil || elapsed > 100_000_000 || previousTuning != tuning
      || calibrationRevision != sample.calibrationRevision || previous?.basis != timestamp.basis
      || calibrationSource != sample.calibrationSource
      || previous?.tickNanosecondsNumerator != timestamp.tickNanosecondsNumerator
      || previous?.tickNanosecondsDenominator != timestamp.tickNanosecondsDenominator
    previous = timestamp
    calibrationSource = sample.calibrationSource
    calibrationRevision = sample.calibrationRevision
    previousTuning = tuning
    if discontinuity { resetEstimates() }
    if elapsed == 0, !discontinuity { return nil }
    let deltaTime = discontinuity ? 0 : Double(elapsed) / 1_000_000_000
    let corrected = bias.update(reading, deltaTime: deltaTime, automatic: tuning.automaticBias)
    guard
      let fused = fusion.update(
        gyro: corrected,
        acceleration: reading.accelerationG,
        deltaTime: deltaTime,
        gravityCorrectionRate: tuning.gravityCorrectionRate
      )
    else {
      latest = nil
      return nil
    }
    guard
      let projected = RemappingMotionProjection.project(
        corrected,
        gravity: fused.gravityG,
        space: tuning.space,
        yawRelaxation: tuning.yawRelaxation,
        sideReductionThreshold: tuning.sideReductionThreshold
      ), let tuned = transform.apply(projected, deltaTime: deltaTime, tuning: tuning)
    else {
      latest = nil
      return nil
    }
    let result = RemappingProcessedMotion(
      timestamp: timestamp,
      deltaTime: deltaTime,
      fused: fused,
      tunedGyro: tuned
    )
    latest = result
    return result
  }

  private mutating func resetEstimates() {
    isManuallyCalibrating = false
    bias.reset()
    fusion.reset()
    transform = RemappingMotionTransform()
    latest = nil
  }

  private static func withinBounds(_ value: ControllerMotionVector, limit: Double) -> Bool {
    value.isFinite && max(abs(value.x), abs(value.y), abs(value.z)) <= limit
  }
}
