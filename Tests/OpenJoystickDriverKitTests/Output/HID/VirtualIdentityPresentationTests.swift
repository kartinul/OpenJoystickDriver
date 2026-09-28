import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualIdentityPresentationTests {
  @Test
  func microsoftIdentitiesUseXboxSymbols() {
    #expect(VirtualDeviceProfile.xboxOneS.presentation == .xbox)
    #expect(VirtualDeviceProfile.xboxOneS.presentation.controllerSymbolName == "xbox.logo")
  }

  @Test
  func genericHIDUsesGenericSymbol() {
    #expect(VirtualDeviceProfile.openJoystickDriverGenericHID.presentation == .generic)
  }

  @Test
  func publishedUSBIdentityLabelsNameTheOfficialProduct() {
    let xboxOneS = VirtualDeviceProfile.xboxOneS
    #expect(xboxOneS.productName == "Xbox Wireless Controller")
    #expect(xboxOneS.publishedUSBIdentityLabel == "Xbox Wireless Controller (045E:02FD)")
    #expect(xboxOneS.presentation.glyphFamily == .xbox)
    #expect(xboxOneS.presentation.controllerSymbolName == "xbox.logo")
  }
}
