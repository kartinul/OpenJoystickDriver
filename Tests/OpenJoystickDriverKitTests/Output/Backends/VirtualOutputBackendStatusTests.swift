import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualOutputBackendStatusTests {
  @Test(arguments: [
    (VirtualOutputBackendStatus.off, "off"),
    (.backend("automatic, targets: xbox-one"), "automatic, targets: xbox-one"),
    (.error("createFailed; live: automatic"), "error: createFailed; live: automatic"),
  ])
  func wireValueRoundTripsThroughParserAndJSON(
    status: VirtualOutputBackendStatus,
    wireValue: String
  ) throws {
    #expect(status.wireValue == wireValue)
    #expect(VirtualOutputBackendStatus(wireValue: wireValue) == status)
    let json = try JSONEncoder().encode([status])
    #expect(String(bytes: json, encoding: .utf8) == "[\"\(wireValue)\"]")
    #expect(try JSONDecoder().decode([VirtualOutputBackendStatus].self, from: json) == [status])
  }

  @Test
  func diagnosticsPayloadCarriesStatusAsWireString() throws {
    let payload = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .error("createFailed"),
      hidGamepads: []
    )
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
    let object = try #require(json as? [String: Any])
    #expect(object["userSpaceVirtualDeviceStatus"] as? String == "error: createFailed")
  }
}
