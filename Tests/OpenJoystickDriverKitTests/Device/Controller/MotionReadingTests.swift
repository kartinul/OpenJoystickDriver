import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionReadingTests {
  private let timestamp = ControllerSampleTimestamp(
    rawCounter: 3,
    monotonic: MonotonicTimestamp(nanoseconds: 0),
    tickNanosecondsNumerator: 1000,
    tickNanosecondsDenominator: 3,
    sequenceIndex: 0
  )

  @Test
  func rejectsNonfiniteSIVectors() {
    #expect(
      ControllerMotionSample(
        timestamp: timestamp,
        acceleration: ControllerMotionVector(x: 0, y: 0, z: 9.8),
        angularVelocity: ControllerMotionVector(x: .nan, y: 0, z: 0),
        calibrationSource: .nominalDeviceScale
      ) == nil
    )
    #expect(
      ControllerMotionSample(
        timestamp: timestamp,
        canonicalDegreesPerSecond: ControllerMotionVector(x: 0, y: 0, z: 0),
        canonicalG: ControllerMotionVector(x: 0, y: .infinity, z: 0),
        calibrationSource: .nominalDeviceScale
      ) == nil
    )
  }

  @Test
  func scalesDegreesAndGravitiesToSIWithoutMovingAxes() throws {
    let sample = try #require(
      ControllerMotionSample(
        timestamp: timestamp,
        canonicalDegreesPerSecond: ControllerMotionVector(x: 180, y: -90, z: 0),
        canonicalG: ControllerMotionVector(x: 0, y: -1, z: 2),
        calibrationSource: .deviceFactory,
        calibrationRevision: 4
      )
    )
    #expect(isClose(sample.angularVelocity, ControllerMotionVector(x: .pi, y: -.pi / 2, z: 0)))
    #expect(isClose(sample.acceleration, ControllerMotionVector(x: 0, y: -9.80665, z: 19.6133)))
    #expect(sample.calibrationSource == .deviceFactory)
    #expect(sample.calibrationRevision == 4)
  }

  @Test
  func sampleRoundTripsWithSIFieldsOnly() throws {
    let sample = try #require(
      ControllerMotionSample(
        timestamp: timestamp,
        acceleration: ControllerMotionVector(x: 0.5, y: -1, z: 9.8),
        angularVelocity: ControllerMotionVector(x: 0.25, y: 0, z: -0.125),
        calibrationSource: .nominalDeviceScale
      )
    )
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "timestamp", "acceleration", "angularVelocity", "calibrationSource", "calibrationRevision",
      ]
    )
    #expect(try JSONDecoder().decode(ControllerMotionSample.self, from: data) == sample)
  }

  @Test
  func decodingCannotBypassFiniteValidation() throws {
    let data = Data(
      #"""
      {
        "timestamp": {
          "basis": "deviceCounter", "rawCounter": 0, "monotonic": {"nanoseconds": 0},
          "sequenceIndex": 0
        },
        "acceleration": {"x":0,"y":0,"z":9.8},
        "angularVelocity": {"x":"inf","y":0,"z":0},
        "calibrationSource": "nominalDeviceScale",
        "calibrationRevision": 0
      }
      """#.utf8
    )
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "inf",
      negativeInfinity: "-inf",
      nan: "nan"
    )
    #expect(throws: DecodingError.self) {
      try decoder.decode(ControllerMotionSample.self, from: data)
    }
  }
}
