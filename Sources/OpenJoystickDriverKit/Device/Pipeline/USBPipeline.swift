import Foundation

/// Checks whether USB startup can continue after the device rejects one startup write.
public func isIgnorableUSBStartupOutputError(
  _ write: PhysicalOutputWrite,
  error: USBTransportError
) -> Bool {
  guard case .usb(_, toleratesRejection: true) = write else { return false }
  switch error {
  case .inputOutput, .notFound, .notSupported, .timeout: return true
  default: return false
  }
}
