import Testing
@testable import OpenJoystickDriverKit

struct PhysicalHIDIdentityTests {
  @Test
  func identityRequiresBothObservedIdentifiers() {
    #expect(PhysicalHIDIdentity(vendorID: nil, productID: 0x1234) == nil)
    #expect(PhysicalHIDIdentity(vendorID: 0x1234, productID: nil) == nil)
    #expect(PhysicalHIDIdentity(vendorID: nil, productID: nil) == nil)
  }

  @Test
  func identityRejectsIdentifiersThatWouldBeTruncated() {
    #expect(PhysicalHIDIdentity(vendorID: 0x1_0000, productID: 0x1234) == nil)
    #expect(PhysicalHIDIdentity(vendorID: 0x1234, productID: 0x1_0000) == nil)
  }

  @Test
  func identityPreservesRepresentableBoundaryValues() throws {
    let identity = try #require(PhysicalHIDIdentity(vendorID: 0xFFFF, productID: 0xFFFF))

    #expect(identity.vendorID == .max)
    #expect(identity.productID == .max)
  }
}
