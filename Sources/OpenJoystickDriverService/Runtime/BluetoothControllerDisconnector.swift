import Foundation
import IOBluetooth
import OpenJoystickDriverKit

final class BluetoothControllerDisconnector: WirelessControllerDisconnecting, Sendable {
  struct CloseResult: Sendable, Equatable {
    let status: IOReturn
    let isConnected: Bool
  }

  private let closeConnection: @Sendable (String, UInt64) -> CloseResult

  init(
    closeConnection: @escaping @Sendable (String, UInt64) -> CloseResult = { address, timeout in
      guard let device = IOBluetoothDevice(addressString: address) else {
        return CloseResult(status: kIOReturnNotFound, isConnected: false)
      }
      let status = device.closeConnection()
      guard status == kIOReturnSuccess else {
        return CloseResult(status: status, isConnected: device.isConnected())
      }
      let deadline = DispatchTime.now().uptimeNanoseconds &+ timeout
      while device.isConnected(), DispatchTime.now().uptimeNanoseconds < deadline {
        Thread.sleep(forTimeInterval: 0.02)
      }
      return CloseResult(status: status, isConnected: device.isConnected())
    }
  ) { self.closeConnection = closeConnection }

  func disconnect(
    address: String,
    timeoutNanoseconds: UInt64
  ) async -> WirelessControllerDisconnectOutcome {
    let outcomes = AsyncStream<WirelessControllerDisconnectOutcome> { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let result = self.closeConnection(address, timeoutNanoseconds)
        let outcome: WirelessControllerDisconnectOutcome
        if result.status != kIOReturnSuccess {
          outcome = .failed(result.status)
        } else if result.isConnected {
          outcome = .stillConnected
        } else {
          outcome = .disconnected
        }
        continuation.yield(outcome)
        continuation.finish()
      }
      // A GCD timer, like the close above, so the timeout does not wait for a cooperative thread.
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + .nanoseconds(Int(clamping: timeoutNanoseconds))
      ) {
        continuation.yield(.timedOut)
        continuation.finish()
      }
    }
    for await outcome in outcomes { return outcome }
    return .failed(kIOReturnError)
  }
}
