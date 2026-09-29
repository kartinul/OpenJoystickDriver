import Foundation

let nanosecondsPerMillisecond: Double = 1_000_000

private let nanosecondsPerSecond: Double = 1_000_000_000

struct RemappingTurboOutput {
  let destination: RemappingDestination
  let configuration: RemappingTurbo
  let startedAt: UInt64
  var outputIsDown: Bool

  func isDown(at uptimeNanoseconds: UInt64) -> Bool {
    guard uptimeNanoseconds >= startedAt else { return outputIsDown }
    return (uptimeNanoseconds - startedAt) % periodNanoseconds < onDurationNanoseconds
  }

  func nextTransition(after uptimeNanoseconds: UInt64) -> UInt64 {
    guard uptimeNanoseconds >= startedAt else {
      return Self.saturatingAdd(startedAt, onDurationNanoseconds)
    }
    guard isDown(at: uptimeNanoseconds) == outputIsDown else { return uptimeNanoseconds }

    let phase = (uptimeNanoseconds - startedAt) % periodNanoseconds
    let remaining = outputIsDown ? onDurationNanoseconds - phase : periodNanoseconds - phase
    return Self.saturatingAdd(uptimeNanoseconds, remaining)
  }

  private var periodNanoseconds: UInt64 {
    max(1, UInt64((nanosecondsPerSecond / configuration.repeatRateHz).rounded()))
  }

  private var onDurationNanoseconds: UInt64 {
    max(1, UInt64((Double(periodNanoseconds) * configuration.dutyCycle).rounded()))
  }

  static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}

struct RemappingContinuousOutput {
  let destination: RemappingContinuousDestination
  let amount: Double
}

enum RemappingContinuousDestination: CaseIterable, Hashable {
  case mouseX
  case mouseY
  case scrollX
  case scrollY

  init?(_ destination: RemappingDestination) {
    switch destination {
    case .mouseMovement(.x): self = .mouseX
    case .mouseMovement(.y): self = .mouseY
    case .scroll(.x): self = .scrollX
    case .scroll(.y): self = .scrollY
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .gamepadAxis, .physical: return nil
    }
  }

  func action(amount: Double) -> RemappingSystemInputAction {
    switch self {
    case .mouseX: .mouseMoved(axis: .x, amount: amount)
    case .mouseY: .mouseMoved(axis: .y, amount: amount)
    case .scrollX: .scrolled(axis: .x, amount: amount)
    case .scrollY: .scrolled(axis: .y, amount: amount)
    }
  }
}

enum RemappingHeldOutput: Hashable {
  case key(RemappingKeyboardKey)
  case modifier(RemappingKeyModifier)
  case mouseButton(RemappingMouseButton)

  var releaseAction: RemappingSystemInputAction {
    switch self {
    case .key(let key): .keyUp(key)
    case .modifier(let modifier): .modifierUp(modifier)
    case .mouseButton(let button): .mouseButtonUp(button)
    }
  }

  var releaseOrder: Int {
    switch self {
    case .key: 0
    case .mouseButton: 1
    case .modifier: 2
    }
  }

  var stableName: String {
    switch self {
    case .key(let key): "key:\(key.rawValue)"
    case .modifier(let modifier): "modifier:\(modifier.rawValue)"
    case .mouseButton(let button): "mouse:\(button.rawValue)"
    }
  }
}
