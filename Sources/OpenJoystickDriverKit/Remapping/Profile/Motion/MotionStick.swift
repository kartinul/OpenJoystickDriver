import Foundation

public enum RemappingMotionLeanDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case left
  case right
}

public struct RemappingMotionLean: Codable, Equatable, Hashable, Sendable {
  public let thresholdDegrees: Double
  public let hysteresisDegrees: Double

  public init(thresholdDegrees: Double = 15, hysteresisDegrees: Double = 2) {
    self.thresholdDegrees = thresholdDegrees
    self.hysteresisDegrees = hysteresisDegrees
  }

  public func validate() throws {
    guard thresholdDegrees.isFinite, (1...89).contains(thresholdDegrees),
      hysteresisDegrees.isFinite, (0...30).contains(hysteresisDegrees),
      hysteresisDegrees < thresholdDegrees
    else { throw RemappingMotionTuningError.invalidField("lean") }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case thresholdDegrees
    case hysteresisDegrees
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    thresholdDegrees = try values.decode(Double.self, forKey: .thresholdDegrees)
    hysteresisDegrees = try values.decode(Double.self, forKey: .hysteresisDegrees)
  }
}

public enum RemappingMotionSteeringOutput: String, Codable, CaseIterable, Hashable, Sendable {
  case leftStickX = "left_stick_x"
  case rightStickX = "right_stick_x"

  var axis: RemappingAxis {
    switch self {
    case .leftStickX: .leftStickX
    case .rightStickX: .rightStickX
    }
  }
}

/// Maps gravity-derived controller lean to a virtual steering axis.
public struct RemappingMotionSteering: Codable, Equatable, Hashable, Sendable {
  public let output: RemappingMotionSteeringOutput
  public let deadzoneDegrees: Double
  public let fullScaleDegrees: Double
  public let responseExponent: Double
  public let inverted: Bool

  public init(
    output: RemappingMotionSteeringOutput = .leftStickX,
    deadzoneDegrees: Double = 5,
    fullScaleDegrees: Double = 45,
    responseExponent: Double = 1,
    inverted: Bool = false
  ) {
    self.output = output
    self.deadzoneDegrees = deadzoneDegrees
    self.fullScaleDegrees = fullScaleDegrees
    self.responseExponent = responseExponent
    self.inverted = inverted
  }

  public func validate() throws {
    guard deadzoneDegrees.isFinite, (0...89).contains(deadzoneDegrees), fullScaleDegrees.isFinite,
      (1...90).contains(fullScaleDegrees), deadzoneDegrees < fullScaleDegrees,
      responseExponent.isFinite, (0.1...10).contains(responseExponent)
    else { throw RemappingMotionTuningError.invalidField("steering") }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case output
    case deadzoneDegrees
    case fullScaleDegrees
    case responseExponent
    case inverted
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    output = try values.decode(RemappingMotionSteeringOutput.self, forKey: .output)
    deadzoneDegrees = try values.decode(Double.self, forKey: .deadzoneDegrees)
    fullScaleDegrees = try values.decode(Double.self, forKey: .fullScaleDegrees)
    responseExponent = try values.decode(Double.self, forKey: .responseExponent)
    inverted = try values.decode(Bool.self, forKey: .inverted)
  }
}
