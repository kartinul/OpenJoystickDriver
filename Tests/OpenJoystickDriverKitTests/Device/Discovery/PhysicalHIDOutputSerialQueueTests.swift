import Testing

@testable import OpenJoystickDriverKit

private actor PhysicalHIDOutputOrderRecorder {
  private var values: [Int] = []
  private var firstValueWaiters: [CheckedContinuation<Void, Never>] = []

  func append(_ value: Int) {
    values.append(value)
    if value == 1 {
      for waiter in firstValueWaiters { waiter.resume() }
      firstValueWaiters.removeAll()
    }
  }

  func waitForFirstValue() async {
    if values.contains(1) { return }
    await withCheckedContinuation { firstValueWaiters.append($0) }
  }

  func snapshot() -> [Int] { values }
}

struct PhysicalHIDOutputSerialQueueTests {
  @Test
  func commandsCompleteInSubmissionOrderWithoutInterleaving() async {
    let queue = PhysicalHIDOutputSerialQueue()
    let recorder = PhysicalHIDOutputOrderRecorder()

    let first = Task {
      await queue.perform { _ in
        await recorder.append(1)
        await Task.yield()
        await recorder.append(2)
        return true
      }
    }
    await recorder.waitForFirstValue()
    let second = Task {
      await queue.perform { _ in
        await recorder.append(3)
        return true
      }
    }

    #expect(await first.value == .completed(true))
    #expect(await second.value == .completed(true))
    #expect(await recorder.snapshot() == [1, 2, 3])
  }

  @Test
  func cancelAllDropsQueuedOperationsAndRunsLaterOnes() async {
    let queue = PhysicalHIDOutputSerialQueue()
    let recorder = PhysicalHIDOutputOrderRecorder()
    let started = StartupTestGate()
    let release = StartupTestGate()
    let running = Task {
      await queue.perform { _ in
        await started.open()
        await release.wait()
        await recorder.append(1)
        return true
      }
    }
    await started.wait()
    let queued = Task {
      await queue.perform { _ in
        await recorder.append(2)
        return true
      }
    }
    while await queue.submittedOperationCount < 2 { await Task.yield() }
    queue.cancelAll()
    let later = Task {
      await queue.perform { _ in
        await recorder.append(3)
        return true
      }
    }
    while await queue.submittedOperationCount < 3 { await Task.yield() }
    await release.open()

    #expect(await running.value == .completed(true))
    #expect(await queued.value == .cancelled)
    #expect(await later.value == .completed(true))
    #expect(await recorder.snapshot() == [1, 3])
  }
}
