import Foundation

@testable import OpenJoystickDriverKit

extension DevicePipeline {
  func activateForTesting() { isActive = true }
  func setUSBHandleForTesting(_ handle: any USBTransportSession) { usbHandle = handle }
  func usbRunTaskForTesting() -> Task<Void, Never>? { runTask }
}

extension DeviceManager {
  func setPhysicalOutputForTesting(
    _ output: RemappingPhysicalOutput,
    owner: UUID,
    identifier: DeviceIdentifier
  ) -> PhysicalOutputChannel {
    physicalOutputOwnership.setMapping(output, active: true, owner: owner, for: identifier)
  }

  var mappingClaimCountForTesting: Int { physicalOutputOwnership.mappingClaimCount }
}
