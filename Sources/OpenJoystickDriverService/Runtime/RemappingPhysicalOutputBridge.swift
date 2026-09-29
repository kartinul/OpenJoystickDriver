import Foundation
import OpenJoystickDriverKit

final class RemappingPhysicalOutputBridge: RemappingPhysicalOutputSink, Sendable {
  private struct WeakManager { weak var manager: DeviceManager? }

  private let attached = Locked(WeakManager())

  func attach(_ manager: DeviceManager) { attached.withLock { $0.manager = manager } }

  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    guard
      await manager.setMappingPhysicalOutput(output, active: active, owner: owner, for: identifier)
    else { throw RemappingEventEngineError.sinkUnavailable }
  }

  func releaseAll(for identifier: DeviceIdentifier) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    guard await manager.releaseMappingPhysicalOutputs(for: identifier) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }

  func setProfileColor(_ color: ControllerColor?, for identifier: DeviceIdentifier) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    guard await manager.setProfilePhysicalColor(color, for: identifier) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }
}
