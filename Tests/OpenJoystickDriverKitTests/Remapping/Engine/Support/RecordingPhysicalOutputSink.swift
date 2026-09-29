import Foundation

@testable import OpenJoystickDriverKit

final class RecordingPhysicalOutputSink: RemappingPhysicalOutputSink, @unchecked Sendable {
  enum Event: Equatable {
    case set(RemappingPhysicalOutput, Bool, UUID, DeviceIdentifier)
    case releaseAll(DeviceIdentifier)
  }

  private let lock = NSLock()
  private var recorded: [Event] = []
  private let rejectSets: Bool

  init(rejectSets: Bool = false) { self.rejectSets = rejectSets }

  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) throws {
    lock.withLock { recorded.append(.set(output, active, owner, identifier)) }
    if rejectSets { throw RemappingEventEngineError.sinkUnavailable }
  }

  func releaseAll(for identifier: DeviceIdentifier) throws {
    lock.withLock { recorded.append(.releaseAll(identifier)) }
  }

  func events() -> [Event] { lock.withLock { recorded } }
}
