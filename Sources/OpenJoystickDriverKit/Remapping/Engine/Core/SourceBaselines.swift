import Foundation

/// One input change the engine applies, found by diffing a source's snapshot against its baseline.
/// Axes are in the remapping frame: Y points down.
enum RemappingInputChange: Equatable {
  case button(RemappingButton, isPressed: Bool)
  case dpad(HatDirection)
  case leftStick(x: Float, y: Float)
  case rightStick(x: Float, y: Float)
  case leftTrigger(Float)
  case rightTrigger(Float)
  case motion(ControllerMotionSample)
  case touch(ControllerTouchSample)
}

extension RemappingEngineState {
  /// Diffs `event` against the last snapshot `source` delivered and applies the changes to
  /// `target`. Each source keeps its own baseline, so two sources feeding one target (a Joy-Con
  /// pair) never release each other's controls.
  mutating func process(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from source: DeviceIdentifier,
    into target: DeviceIdentifier,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    let baseline = sourceBaselines[source] ?? .neutral
    sourceBaselines[source] = event.state
    let changes =
      Self.changes(from: baseline, to: event.state, labels: labels)
      + event.motion.map(RemappingInputChange.motion)
      + event.touchFrames.map(RemappingInputChange.touch)
    return process(changes: changes, from: target, profile: profile, at: uptimeNanoseconds)
  }

  /// Changes from `old` to `new` in the order the delta pipeline delivered them: buttons in parser
  /// label order, then the hat, left stick, right stick, left trigger and right trigger.
  static func changes(
    from old: ControllerState,
    to new: ControllerState,
    labels: ControllerButtonLabels
  ) -> [RemappingInputChange] {
    var changes: [RemappingInputChange] = []
    for control in controlOrder(labels) {
      let isPressed = new.pressed.contains(control)
      guard old.pressed.contains(control) != isPressed,
        let button = RemappingButton(control: control, labels: labels)
      else { continue }
      changes.append(.button(button, isPressed: isPressed))
    }
    if old.hat != new.hat { changes.append(.dpad(new.hat)) }
    if old.leftStick != new.leftStick {
      changes.append(.leftStick(x: new.leftStick.x.normalized, y: -new.leftStick.y.normalized))
    }
    if old.rightStick != new.rightStick {
      changes.append(.rightStick(x: new.rightStick.x.normalized, y: -new.rightStick.y.normalized))
    }
    if old.leftTrigger != new.leftTrigger {
      changes.append(.leftTrigger(new.leftTrigger.normalized))
    }
    if old.rightTrigger != new.rightTrigger {
      changes.append(.rightTrigger(new.rightTrigger.normalized))
    }
    return changes
  }

  /// Digital controls in the order the delta pipeline delivered their changes: the declaration
  /// order of the parser button each family's parsers spelled them with (Xbox spelling for the
  /// standard and Nintendo families, PlayStation spelling, stick clicks first, for PlayStation).
  static func controlOrder(_ labels: ControllerButtonLabels) -> [ControlID] {
    switch labels {
    case .standard: standardControlOrder
    case .nintendo: nintendoControlOrder
    case .playStation: playStationControlOrder
    }
  }

  private static let extraControlOrder: [ControlID] = [
    .paddleLeft2, .paddleRight2, .leftTrackpadClick, .rightTrackpadClick, .auxiliary3, .auxiliary4,
    .auxiliary5, .auxiliary6, .auxiliary1, .auxiliary2, .paddleLeft1, .paddleRight1,
  ]

  private static let standardControlOrder: [ControlID] =
    [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .leftStickClick,
      .rightStickClick, .menu, .view, .guide, .leftTriggerButton, .rightTriggerButton, .share,
      .touchpadClick, .microphone,
    ] + extraControlOrder

  private static let nintendoControlOrder: [ControlID] =
    [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .leftStickClick,
      .rightStickClick, .menu, .view, .guide, .leftTriggerButton, .rightTriggerButton, .capture,
      .touchpadClick, .microphone,
    ] + extraControlOrder

  private static let playStationControlOrder: [ControlID] =
    [
      .leftStickClick, .rightStickClick, .faceSouth, .faceEast, .faceWest, .faceNorth,
      .leftShoulder, .rightShoulder, .leftTriggerButton, .rightTriggerButton, .view, .menu, .guide,
      .touchpadClick, .microphone,
    ] + extraControlOrder
}
