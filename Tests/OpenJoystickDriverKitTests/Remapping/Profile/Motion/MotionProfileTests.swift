import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionProfileTests {
  private func profile(tuning: RemappingMotionTuning = .default) -> RemappingProfile {
    RemappingProfile(
      name: "Motion",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: tuning,
      bindings: []
    )
  }

  @Test
  func profileRoundTripPreservesMotionTuning() throws {
    let custom = profile(tuning: RemappingMotionTuning(space: .world, yawSensitivity: 3))
    try custom.validate()
    let data = try JSONEncoder().encode(custom)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == custom)
  }

  @Test
  func profileValidationRejectsInvalidProgrammaticTuning() {
    let expected = RemappingValidationError.invalidMotionTuning(.invalidField("yaw_sensitivity"))
    #expect(throws: expected) {
      try profile(tuning: RemappingMotionTuning(yawSensitivity: .infinity)).validate()
    }
  }
}
