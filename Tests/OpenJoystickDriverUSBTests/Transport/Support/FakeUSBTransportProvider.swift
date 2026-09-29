import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverUSB

actor FakeUSBTransportProvider: USBTransportProvider {
  private let devicesResult: Result<[USBTransportDevice], USBTransportError>
  private let openResult: Result<any USBTransportSession, USBTransportError>
  private(set) var openCount = 0

  init(
    devicesResult: Result<[USBTransportDevice], USBTransportError> = .success([]),
    openResult: Result<any USBTransportSession, USBTransportError> = .success(
      FakeUSBTransportSession()
    )
  ) {
    self.devicesResult = devicesResult
    self.openResult = openResult
  }

  func devices() throws -> [USBTransportDevice] { try devicesResult.get() }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession {
    openCount += 1
    return try openResult.get()
  }
}

private final class FakeUSBTransportSession: USBTransportSession, @unchecked Sendable {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int { data.count }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] { [] }
}
