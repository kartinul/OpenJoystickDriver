/// Keeps input held across a lifted foreground gate invisible, per field, until that field changes.
///
/// A field whose input still equals the value it had when the mask was taken shows the value last
/// dispatched instead; once it differs it is revealed for the rest of the mask's life.
struct ForegroundInputMask {
  private enum Field: Hashable {
    case control(ControlID)
    case hat
    case leftStick
    case rightStick
    case leftTrigger
    case rightTrigger
  }

  private let hidden: ControllerState
  private var revealed: Set<Field> = []

  init(hiding hidden: ControllerState) { self.hidden = hidden }

  /// `input` with every still-hidden field taken from `shown`.
  mutating func visible(_ input: ControllerState, shown: ControllerState) -> ControllerState {
    var visible = input
    for control in input.pressed.union(hidden.pressed).union(shown.pressed) {
      let isPressed = input.pressed.contains(control)
      if reveals(.control(control), isPressed != hidden.pressed.contains(control)) { continue }
      if shown.pressed.contains(control) {
        visible.pressed.insert(control)
      } else {
        visible.pressed.remove(control)
      }
    }
    if !reveals(.hat, input.hat != hidden.hat) { visible.hat = shown.hat }
    if !reveals(.leftStick, input.leftStick != hidden.leftStick) {
      visible.leftStick = shown.leftStick
    }
    if !reveals(.rightStick, input.rightStick != hidden.rightStick) {
      visible.rightStick = shown.rightStick
    }
    if !reveals(.leftTrigger, input.leftTrigger != hidden.leftTrigger) {
      visible.leftTrigger = shown.leftTrigger
    }
    if !reveals(.rightTrigger, input.rightTrigger != hidden.rightTrigger) {
      visible.rightTrigger = shown.rightTrigger
    }
    return visible
  }

  /// Records `field` as revealed when it `changed`; true once it is revealed.
  private mutating func reveals(_ field: Field, _ changed: Bool) -> Bool {
    if changed { revealed.insert(field) }
    return revealed.contains(field)
  }
}
