import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// The `controller list` line and `status --json` show the observed USB interface number, so the
/// HID parent-interface walk can be checked against `ioreg` on hardware.
struct DeviceListLineTests {
  @Test
  func listLineShowsTheObservedInterfaceOnlyWhenPresent() {
    let observed = Self.description(interfaceNumber: 3)
    #expect(
      ApplicationServiceServer.deviceDescriptionLine(observed).hasPrefix(
        "Wireless Controller (VID:1356 PID:2508 [USB] SN:none) if=3 protocol="
      )
    )
    let unobserved = Self.description(interfaceNumber: nil)
    #expect(!ApplicationServiceServer.deviceDescriptionLine(unobserved).contains(" if="))
  }

  @Test
  func listLineNotesASerialWithoutRevealingIt() {
    let line = ApplicationServiceServer.deviceDescriptionLine(
      Self.description(interfaceNumber: nil, serialNumber: "SERIAL-SECRET-123")
    )
    #expect(line.contains("SN:present"))
    #expect(!line.contains("SERIAL-SECRET-123"))
  }

  @Test
  func statusJSONCarriesTheObservedInterface() throws {
    let data = try JSONEncoder().encode(Self.description(interfaceNumber: 3))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["interfaceNumber"] as? Int == 3)
    let decoded = try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: data)
    #expect(decoded.interfaceNumber == 3)
    let unobserved = try JSONEncoder().encode(Self.description(interfaceNumber: nil))
    let unobservedObject = try JSONSerialization.jsonObject(with: unobserved) as? [String: Any]
    #expect(unobservedObject?["interfaceNumber"] == nil)
  }

  private static func description(
    interfaceNumber: UInt8?,
    serialNumber: String? = nil
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Wireless Controller",
      vendorID: 0x054C,
      productID: 0x09CC,
      protocolBinding: ProtocolBindingID(.sonyDualShock4, variant: .usb),
      connection: "USB",
      interfaceNumber: interfaceNumber,
      discoverySource: .rawUSB,
      serialNumber: serialNumber,
      bindingResult: .hidDescriptorFixture
    )
  }
}
