/// A HID device OJD left to macOS.
public struct PassThroughDeviceSnapshot: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let connection: String

  public init(vendorID: UInt16, productID: UInt16, connection: String) {
    self.vendorID = vendorID
    self.productID = productID
    self.connection = connection
  }
}
