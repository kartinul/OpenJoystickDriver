import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriver

struct SystemPowerNotificationObserverTests {
  @Test
  func deliversSleepAndWakeInFIFOOrderToOneAsyncHandler() async {
    let center = NotificationCenter()
    let recorder = PowerNotificationRecorder(blockWillSleep: true)
    let observer = SystemPowerNotificationObserver(notificationCenter: center) { event in
      await recorder.receive(event)
    }

    observer.start()
    observer.start()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    await recorder.waitForEventCount(1)
    await recorder.waitForSleepHandlerSuspended()
    center.post(name: NSWorkspace.didWakeNotification, object: nil)

    try? await Task.sleep(for: .milliseconds(20))
    #expect(await recorder.events == [.willSleep])

    await recorder.resumeWillSleep()
    await recorder.waitForEventCount(2)
    #expect(await recorder.events == [.willSleep, .didWake])
    await observer.stop()
  }

  @Test
  func stopJoinsInFlightHandlerAndDropsBufferedEvents() async {
    let center = NotificationCenter()
    let recorder = PowerNotificationRecorder(blockWillSleep: true)
    let observer = SystemPowerNotificationObserver(notificationCenter: center) { event in
      await recorder.receive(event)
    }

    observer.start()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    await recorder.waitForEventCount(1)
    await recorder.waitForSleepHandlerSuspended()
    center.post(name: NSWorkspace.didWakeNotification, object: nil)

    let completion = StopCompletionRecorder()
    let firstStop = Task {
      await observer.stop()
      await completion.recordReturn()
    }
    let secondStop = Task {
      await observer.stop()
      await completion.recordReturn()
    }
    await recorder.waitForHandlerCancellation()

    #expect(await completion.returnCount == 0)
    #expect(await recorder.events == [.willSleep])

    await recorder.resumeWillSleep()
    await firstStop.value
    await secondStop.value
    #expect(await completion.returnCount == 2)
    #expect(await recorder.events == [.willSleep])
  }

  @Test
  func stopRemovesObserversAndIsIdempotent() async {
    let center = NotificationCenter()
    let recorder = PowerNotificationRecorder(blockWillSleep: false)
    let observer = SystemPowerNotificationObserver(notificationCenter: center) { event in
      await recorder.receive(event)
    }

    observer.start()
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    await recorder.waitForEventCount(1)

    await observer.stop()
    await observer.stop()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    observer.start()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(await recorder.events == [.didWake])
  }
}

private actor PowerNotificationRecorder {
  private let blockWillSleep: Bool
  private var storedEvents: [SystemPowerNotificationObserver.Event] = []
  private var eventCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var sleepContinuation: CheckedContinuation<Void, Never>?
  private var sleepGateReady = false
  private var sleepGateWaiter: CheckedContinuation<Void, Never>?
  private var handlerCancellationObserved = false
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

  init(blockWillSleep: Bool) { self.blockWillSleep = blockWillSleep }

  var events: [SystemPowerNotificationObserver.Event] { storedEvents }

  func receive(_ event: SystemPowerNotificationObserver.Event) async {
    storedEvents.append(event)
    let ready = eventCountWaiters.filter { $0.0 <= storedEvents.count }
    eventCountWaiters.removeAll { $0.0 <= storedEvents.count }
    for (_, continuation) in ready { continuation.resume() }
    if blockWillSleep, event == .willSleep {
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          sleepContinuation = continuation
          sleepGateReady = true
          sleepGateWaiter?.resume()
          sleepGateWaiter = nil
        }
      } onCancel: {
        Task { await self.recordHandlerCancellation() }
      }
    }
  }

  func waitForEventCount(_ count: Int) async {
    guard storedEvents.count < count else { return }
    await withCheckedContinuation { eventCountWaiters.append((count, $0)) }
  }

  func waitForSleepHandlerSuspended() async {
    guard !sleepGateReady else { return }
    await withCheckedContinuation { sleepGateWaiter = $0 }
  }

  func waitForHandlerCancellation() async {
    guard !handlerCancellationObserved else { return }
    await withCheckedContinuation { cancellationWaiters.append($0) }
  }

  private func recordHandlerCancellation() {
    handlerCancellationObserved = true
    for continuation in cancellationWaiters { continuation.resume() }
    cancellationWaiters.removeAll()
  }

  func resumeWillSleep() {
    sleepContinuation?.resume()
    sleepContinuation = nil
  }
}

private actor StopCompletionRecorder {
  private(set) var returnCount = 0

  func recordReturn() { returnCount += 1 }
}
