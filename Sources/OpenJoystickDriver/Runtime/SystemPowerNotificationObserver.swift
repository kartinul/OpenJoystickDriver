import AppKit
import Foundation

final class SystemPowerNotificationObserver: @unchecked Sendable {
  enum Event: Equatable, Sendable {
    case willSleep
    case didWake
  }

  typealias Handler = @Sendable (Event) async -> Void

  private let notificationCenter: NotificationCenter
  private let handler: Handler
  private let lock = NSLock()
  private var observerTokens: [NSObjectProtocol] = []
  private var eventContinuation: AsyncStream<Event>.Continuation?
  private var deliveryTask: Task<Void, Never>?
  private var stopTask: Task<Void, Never>?
  private var started = false
  private var stopped = false

  @MainActor
  convenience init(handler: @escaping Handler) {
    self.init(notificationCenter: NSWorkspace.shared.notificationCenter, handler: handler)
  }

  init(notificationCenter: NotificationCenter, handler: @escaping Handler) {
    self.notificationCenter = notificationCenter
    self.handler = handler
  }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard !started, !stopped else { return }
    started = true
    let eventStream = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
    eventContinuation = eventStream.continuation
    let handler = self.handler
    deliveryTask = Task { [weak self] in
      for await event in eventStream.stream {
        guard !Task.isCancelled, self?.canDeliver == true else { return }
        await handler(event)
      }
    }
    observerTokens = [
      notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.enqueue(.willSleep) },
      notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.enqueue(.didWake) },
    ]
  }

  func stop() async { await beginStop().value }

  private func beginStop() -> Task<Void, Never> {
    lock.lock()
    guard let stopTask else {
      stopped = true
      started = false
      let tokens = observerTokens
      observerTokens.removeAll()
      eventContinuation?.finish()
      eventContinuation = nil
      let deliveryTask = deliveryTask
      let notificationCenter = notificationCenter
      let task = Task {
        for token in tokens { notificationCenter.removeObserver(token) }
        if let deliveryTask {
          deliveryTask.cancel()
          await deliveryTask.value
        }
      }
      stopTask = task
      lock.unlock()
      return task
    }
    lock.unlock()
    return stopTask
  }

  deinit {
    deliveryTask?.cancel()
    eventContinuation?.finish()
    for token in observerTokens { notificationCenter.removeObserver(token) }
  }

  private func enqueue(_ event: Event) {
    lock.lock()
    guard started, !stopped else {
      lock.unlock()
      return
    }
    eventContinuation?.yield(event)
    lock.unlock()
  }

  private var canDeliver: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started && !stopped
  }
}
