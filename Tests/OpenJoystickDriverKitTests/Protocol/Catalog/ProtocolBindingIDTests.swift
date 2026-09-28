import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolBindingIDTests {
  @Test
  func writesFamilyAndOptionalVariant() {
    #expect(ProtocolBindingID(.xboxXUSB, variant: .receiver).rawValue == "xbox.xusb:receiver")
    #expect(ProtocolBindingID(.vendorFlydigi).rawValue == "vendor.flydigi")
    #expect(
      ProtocolBindingID(rawValue: "sony.dualshock4:bluetooth-classic")
        == ProtocolBindingID(.sonyDualShock4, variant: .bluetoothClassic)
    )
  }

  @Test(arguments: [
    "", "xbox.xusb:", "xboxOne", "GIP", "xbox.gip:usb:usb", "sony.dualsense:receiver",
    "vendor.flydigi:usb", "xbox.xusb:xbox360Wireless", "vendor.gamesir:enhanced-hid-8k",
    // A binding is resolved: families with variants always name one.
    "xbox.gip", "xbox.xusb", "vendor.gamesir", "sony.dualsense",
  ])
  func rejectsUnknownFamiliesAndVariantsOutsideTheFamily(_ text: String) throws {
    #expect(ProtocolBindingID(rawValue: text) == nil)
    let json = try JSONEncoder().encode([text])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([ProtocolBindingID].self, from: json)
    }
  }

  @Test
  func rawUSBRowsReportTheirResolvedBinding() throws {
    let registry = ProtocolDriverRegistry()
    let gip = try #require(
      registry.record(for: DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA))
    )
    let receiver = try #require(
      registry.record(for: DeviceIdentifier(vendorID: 0x045E, productID: 0x0719))
    )
    let dualSense = try #require(
      registry.record(for: DeviceIdentifier(vendorID: 0x054C, productID: 0x0CE6))
    )
    #expect(gip.rawUSBBinding?.rawValue == "xbox.gip:usb")
    #expect(receiver.rawUSBBinding?.rawValue == "xbox.xusb:receiver")
    #expect(dualSense.rawUSBBinding == nil)
  }

  @Test
  func encodesAsItsWrittenForm() throws {
    let binding = ProtocolBindingID(.valveSteamController, variant: .dongle)
    let json = try JSONEncoder().encode([binding])
    #expect(String(bytes: json, encoding: .utf8) == #"["valve.steam-controller:dongle"]"#)
    #expect(try JSONDecoder().decode([ProtocolBindingID].self, from: json) == [binding])
  }
}
