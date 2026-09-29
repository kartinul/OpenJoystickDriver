import Foundation

/// Normalized gamepad output owned by one exact remapping session.
public struct RemappingGamepadState: Equatable, Sendable {
  public let buttons: Set<RemappingButton>
  public let dpad: Set<RemappingDpadDirection>
  public let axes: [RemappingAxis: Double]

  public init(
    buttons: Set<RemappingButton> = [],
    dpad: Set<RemappingDpadDirection> = [],
    axes: [RemappingAxis: Double] = [:]
  ) {
    self.buttons = buttons.filter(\.supportsVirtualOutput)
    var directions = dpad
    if directions.contains(.up), directions.contains(.down) { directions.subtract([.up, .down]) }
    if directions.contains(.left), directions.contains(.right) {
      directions.subtract([.left, .right])
    }
    self.dpad = directions
    self.axes = axes.reduce(into: [:]) { result, entry in
      let (axis, value) = entry
      guard value.isFinite else { return }
      let minimum = Self.isTrigger(axis) ? 0.0 : -1.0
      let normalized = min(1, max(minimum, value))
      if normalized != 0 { result[axis] = normalized }
    }
  }

  public static let neutral = Self()

  /// Missing axes are neutral, including after a contribution is released.
  public func value(for axis: RemappingAxis) -> Double { axes[axis, default: 0] }

  static func isTrigger(_ axis: RemappingAxis) -> Bool {
    axis == .leftTrigger || axis == .rightTrigger
  }
}

/// Retains independent binding contributions so releasing one cannot release another.
struct RemappingGamepadAccumulator: Sendable {
  private var contributions: [UUID: RemappingGamepadState] = [:]
  private(set) var state = RemappingGamepadState.neutral

  /// Returns a changed aggregate, including neutral; unchanged aggregates return nil.
  mutating func update(
    _ contribution: RemappingGamepadState,
    for bindingID: UUID
  ) -> RemappingGamepadState? {
    if contribution == .neutral {
      contributions.removeValue(forKey: bindingID)
    } else {
      contributions[bindingID] = contribution
    }
    return recompute()
  }

  mutating func release(_ bindingID: UUID) -> RemappingGamepadState? {
    update(.neutral, for: bindingID)
  }

  mutating func drain() -> RemappingGamepadState? {
    contributions.removeAll()
    return recompute()
  }

  private mutating func recompute() -> RemappingGamepadState? {
    var buttons: Set<RemappingButton> = []
    var dpad: Set<RemappingDpadDirection> = []
    var axes: [RemappingAxis: Double] = [:]
    // A stable order makes floating-point aggregation independent of dictionary insertion order.
    for id in contributions.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let contribution = contributions[id] else { continue }
      buttons.formUnion(contribution.buttons)
      dpad.formUnion(contribution.dpad)
      for (axis, value) in contribution.axes {
        if RemappingGamepadState.isTrigger(axis) {
          axes[axis] = max(axes[axis, default: 0], value)
        } else {
          axes[axis, default: 0] += value
        }
      }
    }
    let next = RemappingGamepadState(buttons: buttons, dpad: dpad, axes: axes)
    guard next != state else { return nil }
    state = next
    return next
  }
}

extension RemappingGamepadState {
  /// The hat direction the held d-pad directions form; opposite directions cancel.
  var dpadDirection: HatDirection {
    let horizontal = (dpad.contains(.right) ? 1 : 0) - (dpad.contains(.left) ? 1 : 0)
    let vertical = (dpad.contains(.up) ? 1 : 0) - (dpad.contains(.down) ? 1 : 0)
    switch (horizontal, vertical) {
    case (0, 1): return .north
    case (1, 1): return .northEast
    case (1, 0): return .east
    case (1, -1): return .southEast
    case (0, -1): return .south
    case (-1, -1): return .southWest
    case (-1, 0): return .west
    case (-1, 1): return .northWest
    default: return .neutral
    }
  }
}
