import Foundation

struct CompatibilityTransitionTimeouts: Sendable {
  static let standard = Self(
    stageNanoseconds: 2_000_000_000,
    perControllerNanoseconds: 2_000_000_000,
    totalNanoseconds: 10_000_000_000,
    zeroControllerActivationNanoseconds: 2_000_000_000,
    feedbackNanoseconds: 2_000_000_000,
    candidateCloseNanoseconds: 2_000_000_000
  )

  let stageNanoseconds: UInt64
  let perControllerNanoseconds: UInt64
  let totalNanoseconds: UInt64
  let zeroControllerActivationNanoseconds: UInt64
  let feedbackNanoseconds: UInt64
  let candidateCloseNanoseconds: UInt64

  init(
    stageNanoseconds: UInt64,
    perControllerNanoseconds: UInt64,
    totalNanoseconds: UInt64,
    zeroControllerActivationNanoseconds: UInt64 = 2_000_000_000,
    feedbackNanoseconds: UInt64 = 2_000_000_000,
    candidateCloseNanoseconds: UInt64 = 2_000_000_000
  ) {
    self.stageNanoseconds = stageNanoseconds
    self.perControllerNanoseconds = perControllerNanoseconds
    self.totalNanoseconds = totalNanoseconds
    self.zeroControllerActivationNanoseconds = zeroControllerActivationNanoseconds
    self.feedbackNanoseconds = feedbackNanoseconds
    self.candidateCloseNanoseconds = candidateCloseNanoseconds
  }

  func activationNanoseconds(for count: Int) -> UInt64 {
    guard count > 0 else { return zeroControllerActivationNanoseconds }
    let perController = perControllerNanoseconds.multipliedReportingOverflow(by: UInt64(count))
    return min(perController.overflow ? UInt64.max : perController.partialValue, totalNanoseconds)
  }
}

struct CompatibilityTransitionClock: Sendable {
  static let system = Self(
    now: { DispatchTime.now().uptimeNanoseconds },
    sleep: { nanoseconds in try await Task.sleep(nanoseconds: nanoseconds) }
  )

  let now: @Sendable () -> UInt64
  let sleep: @Sendable (UInt64) async throws -> Void
}
