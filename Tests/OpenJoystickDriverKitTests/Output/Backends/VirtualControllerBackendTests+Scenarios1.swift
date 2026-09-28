import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension VirtualControllerBackendTests {
  @Test
  func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.publishesConsumerGamepad)
    #expect(VirtualControllerBackendID.allCases.contains(.gameControllerHID))
    #expect(!capabilities.notes.isEmpty)
  }

  @Test
  func testUserSpaceSerialUsesStableHashedPhysicalIdentity() {
    let identifier = DeviceIdentifier(
      vendorID: 13623,
      productID: 4112,
      serialNumber: "physical-serial"
    )
    let serial = UserSpaceVirtualDeviceConstants.serialNumber(for: identifier)

    #expect(serial.hasPrefix(UserSpaceVirtualDeviceConstants.serialPrefix))
    #expect(serial.count == UserSpaceVirtualDeviceConstants.serialPrefix.count + 16)
    #expect(serial.suffix(16).allSatisfy { $0.isHexDigit })
    #expect(serial == UserSpaceVirtualDeviceConstants.serialNumber(for: identifier))
  }

  @Test
  func guideDispatchUsesXboxGuideReportContract() {
    #expect(UserSpaceOutputDispatcher.xboxGuideReport(pressed: true) == [0x02, 0x01])
    #expect(UserSpaceOutputDispatcher.xboxGuideReport(pressed: false) == [0x02, 0x00])
  }

  @Test
  func nonStandardButtonsKeepDistinctNormalizedBits() {
    func bit(_ control: ControlID, _ labels: ControllerButtonLabels) -> UInt32? {
      UserSpaceOutputDispatcher.buttonBit(for: control, labels: labels, emitsXboxGuideReport: false)
    }

    #expect(bit(.share, .standard) == 15)
    #expect(bit(.view, .playStation) == 15)
    #expect(bit(.capture, .nintendo) == 15)
    #expect(bit(.view, .standard) == 9)
    #expect(bit(.microphone, .standard) == nil)
    #expect(bit(.touchpadClick, .standard) == nil)
  }

}
