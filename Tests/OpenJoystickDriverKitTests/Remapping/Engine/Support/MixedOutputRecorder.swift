import Foundation

@testable import OpenJoystickDriverKit

final class MixedOutputRecorder: RemappingSystemInputSink, RemappingGamepadSink, @unchecked Sendable
{
  private let lock = NSLock()
  private var recorded: [RemappingEngineAction] = []
  private var rejectsNextGamepad = false

  var actions: [RemappingEngineAction] { lock.withLock { recorded } }

  func rejectNextGamepadSend() { lock.withLock { rejectsNextGamepad = true } }

  func send(_ action: RemappingSystemInputAction) {
    lock.withLock { recorded.append(.system(action)) }
  }

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
    let reject = lock.withLock {
      recorded.append(.gamepad(state, identifier))
      defer { rejectsNextGamepad = false }
      return rejectsNextGamepad
    }
    if reject { throw RemappingEventEngineError.sinkUnavailable }
    await Task.yield()
  }
}
