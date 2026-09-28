import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDProfileDiscoveryTests {
  @Test
  func hidAndRawUSBCatalogPartitionsAreDisjoint() {
    let registry = ProtocolDriverRegistry()
    let hid = Set(
      registry.hidIdentifiers.map {
        "\($0.controllerIdentity.vendorID):\($0.controllerIdentity.productID)"
      }
    )
    let rawUSB = Set(
      registry.rawUSBIdentifiers.map {
        "\($0.controllerIdentity.vendorID):\($0.controllerIdentity.productID)"
      }
    )

    #expect(!hid.isEmpty)
    #expect(!rawUSB.isEmpty)
    #expect(hid.isDisjoint(with: rawUSB))
  }
}
