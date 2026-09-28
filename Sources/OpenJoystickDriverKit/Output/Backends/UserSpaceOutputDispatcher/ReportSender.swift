import Foundation

/// One bounded, ordered stream for event reports and host-protocol replies.
/// Closing revokes new submissions and detaches the backend before the active native send drains.
final class UserSpaceReportSender: @unchecked Sendable {
  enum Failure: Error, Equatable, LocalizedError, Sendable {
    case queueOverflow
    case sendTimedOut

    var errorDescription: String? {
      switch self {
      case .queueOverflow: "Virtual controller publication queue overflowed."
      case .sendTimedOut: "Virtual controller publication timed out."
      }
    }
  }

  private static let queueCapacity = 64
  /// Matches the compatibility transition deadline used to retire native virtual devices.
  private static let nativeSendDeadlineNanoseconds: UInt64 = 2_000_000_000

  final class SubmissionReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, any Error>] = []

    func finish(_ result: Result<Void, any Error>) {
      let waiters = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
        guard self.result == nil else { return [] }
        self.result = result
        defer { self.waiters.removeAll() }
        return self.waiters
      }
      for waiter in waiters {
        switch result {
        case .success: waiter.resume()
        case .failure(let error): waiter.resume(throwing: error)
        }
      }
    }

    func value() async throws {
      try await withCheckedThrowingContinuation { continuation in
        let result = lock.withLock { () -> Result<Void, any Error>? in
          if let result = self.result { return result }
          waiters.append(continuation)
          return nil
        }
        if let result {
          switch result {
          case .success: continuation.resume()
          case .failure(let error): continuation.resume(throwing: error)
          }
        }
      }
    }
  }

  private final class NativeSendOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var cancellationRequested = false
    private var sendTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var backend: (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?
    private var completion: (@Sendable (Result<Void, any Error>) -> Void)?

    func start(
      report: [UInt8],
      backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend,
      completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
      lock.withLock {
        self.backend = backend
        self.completion = completion
      }
      let send = Task.detached { [weak self] in
        do {
          try await backend.send(report)
          self?.finish(.success(()))
        } catch { self?.finish(.failure(error)) }
      }
      let deadline = Task.detached { [weak self] in
        do {
          try await Task.sleep(nanoseconds: UserSpaceReportSender.nativeSendDeadlineNanoseconds)
          if self?.isCancellationRequested() == true {
            self?.finish(.failure(CancellationError()))
          } else {
            backend.close()
            self?.finish(.failure(Failure.sendTimedOut))
          }
        } catch {
          // Cancellation only stops the deadline.
        }
      }
      let didComplete = lock.withLock { () -> Bool in
        sendTask = send
        deadlineTask = deadline
        return self.completed
      }
      if didComplete {
        send.cancel()
        deadline.cancel()
      }
    }

    func cancel() {
      let sendTask = lock.withLock { () -> Task<Void, Never>? in
        cancellationRequested = true
        return self.sendTask
      }
      sendTask?.cancel()
    }

    private func isCancellationRequested() -> Bool { lock.withLock { cancellationRequested } }

    private func finish(_ result: Result<Void, any Error>) {
      let completion = lock.withLock { () -> (@Sendable (Result<Void, any Error>) -> Void)? in
        guard !completed else { return nil }
        completed = true
        deadlineTask?.cancel()
        return self.completion
      }
      completion?(result)
    }
  }

  private struct Submission: @unchecked Sendable {
    let completion: SubmissionReceipt
    let whileActive: @Sendable () -> Bool
    let requireActive: Bool
    let reports: @Sendable () throws -> [[UInt8]]
  }

  private let lock = NSLock()
  private var backend: (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?
  private let continuation: AsyncStream<Submission>.Continuation
  private var worker: Task<Void, Never>?
  private var pending: [ObjectIdentifier: SubmissionReceipt] = [:]
  private var active: SubmissionReceipt?
  private var closeTask: Task<Void, Never>?
  private var closed = false

  init() {
    var capturedContinuation: AsyncStream<Submission>.Continuation?
    let stream = AsyncStream<Submission>(bufferingPolicy: .bufferingOldest(Self.queueCapacity)) {
      capturedContinuation = $0
    }
    continuation = capturedContinuation!
    worker = Task { [weak self] in
      for await submission in stream {
        guard let self else {
          submission.completion.finish(.failure(CancellationError()))
          continue
        }
        await self.publish(submission)
      }
    }
  }

  deinit { _ = beginClose() }

  func attach(_ backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend) {
    let rejected = lock.withLock {
      guard !closed, self.backend == nil else { return true }
      self.backend = backend
      return false
    }
    if rejected { backend.close() }
  }

  /// Builds reports in the retained worker only after preceding publication completes.
  func submit(
    whileActive: @escaping @Sendable () -> Bool = { true },
    requireActive: Bool = false,
    _ reports: @escaping @Sendable () throws -> [[UInt8]]
  ) -> SubmissionReceipt {
    let completion = SubmissionReceipt()
    let submission = Submission(
      completion: completion,
      whileActive: whileActive,
      requireActive: requireActive,
      reports: reports
    )
    let result = lock.withLock { () -> Result<Void, any Error>? in
      guard !closed else { return .failure(CancellationError()) }
      let key = ObjectIdentifier(completion)
      pending[key] = completion
      switch continuation.yield(submission) {
      case .enqueued: return nil
      case .dropped:
        pending.removeValue(forKey: key)
        return .failure(Failure.queueOverflow)
      case .terminated:
        pending.removeValue(forKey: key)
        return .failure(CancellationError())
      @unknown default:
        pending.removeValue(forKey: key)
        return .failure(CancellationError())
      }
    }
    if let result { completion.finish(result) }
    return completion
  }

  private func publish(_ submission: Submission) async {
    lock.withLock { active = submission.completion }
    defer {
      lock.withLock {
        pending.removeValue(forKey: ObjectIdentifier(submission.completion))
        if active === submission.completion { active = nil }
      }
    }
    do {
      try Task.checkCancellation()
      let backend = try lock.withLock {
        guard !closed, let backend = self.backend else { throw CancellationError() }
        return backend
      }
      for report in try submission.reports() {
        guard !lock.withLock({ closed }) else { throw CancellationError() }
        guard submission.whileActive() else {
          if submission.requireActive { throw CancellationError() }
          submission.completion.finish(.success(()))
          return
        }
        try await send(report, to: backend)
      }
      submission.completion.finish(.success(()))
    } catch { submission.completion.finish(.failure(error)) }
  }

  private func send(
    _ report: [UInt8],
    to backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend
  ) async throws {
    let operation = NativeSendOperation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        operation.start(report: report, backend: backend) { result in
          switch result {
          case .success: continuation.resume()
          case .failure(let error): continuation.resume(throwing: error)
          }
        }
      }
    } onCancel: {
      operation.cancel()
    }
  }

  @discardableResult
  func beginClose() -> Task<Void, Never> {
    let result = lock.withLock {
      () -> (
        Task<Void, Never>, (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?,
        [SubmissionReceipt]
      ) in
      if let closeTask { return (closeTask, nil, []) }
      closed = true
      continuation.finish()
      let backend = backend
      self.backend = nil
      let activeIdentifier = active.map { ObjectIdentifier($0) }
      let cancellations = pending.compactMap { key, completion in
        key == activeIdentifier ? nil : completion
      }
      pending.removeAll()
      worker?.cancel()
      let worker = worker
      let task = Task { if let worker { await worker.value } }
      closeTask = task
      return (task, backend, cancellations)
    }
    result.1?.close()
    result.2.forEach { $0.finish(.failure(CancellationError())) }
    return result.0
  }
}
