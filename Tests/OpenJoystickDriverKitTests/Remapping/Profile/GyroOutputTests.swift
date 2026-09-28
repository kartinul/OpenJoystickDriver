import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct GyroOutputTests {
  @Test
  func mouseGyroRequiresSystemInputAccessInOtherwiseVirtualOnlyProfiles() throws {
    for mode in RemappingGyroOutputMode.allCases {
      let profile = RemappingProfile(
        name: "Gyro permissions",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
        gyroOutput: RemappingGyroOutput(mode: mode),
        bindings: []
      )
      try profile.validate()
      #expect(profile.requiresSystemInputAccess == (mode == .mouse))
    }
  }

  @Test
  func profilesPersistGyroOutputAndEnforceVirtualOutputPolicy() throws {
    let mouse = profile(output: RemappingGyroOutput(mode: .mouse))
    try mouse.validate()
    let encoded = try JSONEncoder().encode(mouse)
    #expect(String(data: encoded, encoding: .utf8)?.contains("gyroOutput") == true)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: encoded) == mouse)
    for mode in [RemappingGyroOutputMode.leftStick, .rightStick] {
      #expect(throws: RemappingValidationError.virtualOutputRequired) {
        try profile(output: RemappingGyroOutput(mode: mode)).validate()
      }
    }
  }

  private func profile(output: RemappingGyroOutput) -> RemappingProfile {
    RemappingProfile(
      name: "Gyro",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      gyroOutput: output,
      bindings: []
    )
  }

  @Test
  func omittedSettingsDisableOutputAndExplicitSettingsRoundTrip() throws {
    let omitted = try JSONDecoder().decode(RemappingGyroOutput.self, from: Data("{}".utf8))
    #expect(omitted == .default)
    #expect(omitted.mode == .disabled)
    for mode in RemappingGyroOutputMode.allCases {
      let settings = RemappingGyroOutput(
        mode: mode,
        pointerPointsPerDegree: 4.5,
        fullStickDegreesPerSecond: 180
      )
      let encoded = try JSONEncoder().encode(settings)
      #expect(try JSONDecoder().decode(RemappingGyroOutput.self, from: encoded) == settings)
    }
  }

  @Test
  func unknownFieldsAreIgnoredAndNotReencoded() throws {
    let stored = Data(#"{"mode":"mouse","virtualMotion":true}"#.utf8)
    let decoded = try JSONDecoder().decode(RemappingGyroOutput.self, from: stored)
    #expect(decoded == RemappingGyroOutput(mode: .mouse))
    let encoded = try #require(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
    #expect(!encoded.contains("virtualMotion"))
  }

  @Test
  func invalidUnitsAreRejectedAtValidationAndDecode() throws {
    for value in [-1, 1001, Double.nan, Double.infinity] {
      #expect(throws: RemappingGyroOutputError.invalidField("pointer_points_per_degree")) {
        try RemappingGyroOutput(pointerPointsPerDegree: value).validate()
      }
    }
    for value in [0, 10001, Double.nan, Double.infinity] {
      #expect(throws: RemappingGyroOutputError.invalidField("full_stick_degrees_per_second")) {
        try RemappingGyroOutput(fullStickDegreesPerSecond: value).validate()
      }
    }
    #expect(throws: RemappingGyroOutputError.invalidField("full_stick_degrees_per_second")) {
      try JSONDecoder().decode(
        RemappingGyroOutput.self,
        from: Data(#"{"mode":"right_stick","fullStickDegreesPerSecond":0}"#.utf8)
      )
    }
  }
}
