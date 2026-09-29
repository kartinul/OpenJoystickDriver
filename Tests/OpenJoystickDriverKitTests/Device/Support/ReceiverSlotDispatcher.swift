import Foundation

@testable import OpenJoystickDriverKit

/// Records which controllers received input dispatches and which were stopped.
final class ReceiverSlotDispatcher: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var recordedDispatches: [DeviceIdentifier: [ControllerState]] = [:]
  private var recordedStops: [DeviceIdentifier] = []

  var suppressOutput = false
  var dispatches: [DeviceIdentifier: [ControllerState]] { lock.withLock { recordedDispatches } }
  var stops: [DeviceIdentifier] { lock.withLock { recordedStops } }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) { lock.withLock { recordedDispatches[identifier, default: []].append(event.state) } }

  func activateOutput(for _: DeviceIdentifier) {}

  func controllerDidStop(_ identifier: DeviceIdentifier) {
    lock.withLock { recordedStops.append(identifier) }
  }
}

/// Cancels the admitting task at its second inventory change, the moment the second slot's
/// pipeline exists, so that slot's post-start check fails the whole admission. Only a task that
/// binds ``counter`` is affected; other tests post the same notification.
enum ReceiverSlotAdmissionCanceller {
  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var posts = 0

    var count: Int { lock.withLock { posts } }

    func increment() -> Int {
      lock.withLock {
        posts += 1
        return posts
      }
    }
  }

  @TaskLocal
  static var counter: Counter?

  static func observe() -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: .ojdControllerInventoryDidChange,
      object: nil,
      queue: nil
    ) { _ in
      guard let counter, counter.increment() == 2 else { return }
      withUnsafeCurrentTask { $0?.cancel() }
    }
  }
}
