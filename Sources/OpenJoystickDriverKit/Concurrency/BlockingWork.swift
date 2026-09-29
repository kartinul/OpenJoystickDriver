import Foundation

/// Runs synchronous work that may block (socket I/O, native device creation) off the Swift
/// concurrency cooperative pool.
package enum BlockingWork {
  /// Runs `work` on a new serial dispatch queue and resumes the caller once with its outcome.
  ///
  /// Each call gets its own queue, so one blocked operation never delays another.
  package static func run<Value: Sendable>(
    label: String,
    _ work: @escaping @Sendable () throws -> Value
  ) async throws -> Value { try await run(on: DispatchQueue(label: label), work) }

  /// Runs `work` on `queue` and resumes the caller once with its outcome.
  ///
  /// Use a long-lived serial queue for work that is already serialized and runs often, such as
  /// per-report device calls, so each call does not create a queue.
  package static func run<Value: Sendable>(
    on queue: DispatchQueue,
    _ work: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { continuation.resume(with: Result(catching: work)) }
    }
  }
}
