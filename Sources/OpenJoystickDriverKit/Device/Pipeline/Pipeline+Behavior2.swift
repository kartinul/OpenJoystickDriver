import Foundation

extension DevicePipeline {

  func invalidateUSBHandle(_ handle: any USBTransportSession) async {
    guard let current = usbHandle, ObjectIdentifier(current) == ObjectIdentifier(handle) else {
      return
    }
    usbHandle = nil
    stopUSBKeepAlive()
    await handle.close()
    driver.resetProtocolState()
    // The driver forgot presence with the session, so the next session's presence reply must
    // connect the controller again here too.
    if requiresInputConnectionBeforeOutput(), inputConnectionActive { await endInputConnection() }
  }

}
