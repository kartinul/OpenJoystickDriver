import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  public func previewPhysicalColor(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    token: UUID,
    red: Int,
    green: Int,
    blue: Int
  ) async -> Bool {
    guard let red = UInt8(exactly: red), let green = UInt8(exactly: green),
      let blue = UInt8(exactly: blue)
    else { return false }
    let identifier = DeviceIdentifier(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID)
    )
    return await deviceManager.previewPhysicalColor(
      for: identifier,
      runtimeIdentifier: runtimeIdentifier,
      token: token,
      red: red,
      green: green,
      blue: blue
    )
  }

  public func releasePhysicalColorPreview(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    token: UUID
  ) async -> Bool {
    let identifier = DeviceIdentifier(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID)
    )
    return await deviceManager.releasePhysicalColorPreview(
      for: identifier,
      runtimeIdentifier: runtimeIdentifier,
      token: token
    )
  }
}
