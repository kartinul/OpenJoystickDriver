import Foundation
import OpenJoystickDriverKit
import Testing

struct RemappingRouteWireTests {
  @Test
  func routeWireValuesAcceptOnlyCurrentSpellings() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    #expect(
      try encoder.encode([ApplicationServiceRemappingRouteSelection.virtualGamepad])
        == Data(#"["virtual-gamepad"]"#.utf8)
    )
    #expect(
      try encoder.encode([ApplicationServiceRemappingRouteEligibility.virtualOutputSuppressed])
        == Data(#"["virtual_output_suppressed"]"#.utf8)
    )
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        [ApplicationServiceRemappingRouteSelection].self,
        from: Data(#"["compatibility"]"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        [ApplicationServiceRemappingRouteEligibility].self,
        from: Data(#"["compatibility_output_suppressed"]"#.utf8)
      )
    }
  }
}
