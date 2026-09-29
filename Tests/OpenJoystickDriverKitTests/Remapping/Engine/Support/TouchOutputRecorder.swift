import Foundation

@testable import OpenJoystickDriverKit

final class TouchOutputRecorder: RemappingSystemInputSink, RemappingGamepadSink, @unchecked Sendable
{
  private let lock = NSLock()
  private var recordedSystemActions: [RemappingSystemInputAction] = []
  private var recordedGamepadStates: [RemappingGamepadState] = []

  var systemActions: [RemappingSystemInputAction] { lock.withLock { recordedSystemActions } }
  var gamepadStates: [RemappingGamepadState] { lock.withLock { recordedGamepadStates } }

  func send(_ action: RemappingSystemInputAction) {
    lock.withLock { recordedSystemActions.append(action) }
  }

  func send(_ state: RemappingGamepadState, for _: DeviceIdentifier) async {
    await Task.yield()
    lock.withLock { recordedGamepadStates.append(state) }
  }
}
