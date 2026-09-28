import Foundation

private let controllerSleepStickDeadzone: Float = 0.15
private let controllerSleepTriggerDeadzone: Float = 0.05

extension ControllerState {
  /// True when no control is held and every stick and trigger rests within the sleep dead zones.
  var isEffectivelyNeutral: Bool {
    pressed.isEmpty && hat == .neutral && !leftStick.isBeyondSleepDeadzone
      && !rightStick.isBeyondSleepDeadzone && !leftTrigger.isBeyondSleepDeadzone
      && !rightTrigger.isBeyondSleepDeadzone
  }
}

extension StickPosition {
  var isBeyondSleepDeadzone: Bool {
    abs(x.normalized) > controllerSleepStickDeadzone
      || abs(y.normalized) > controllerSleepStickDeadzone
  }
}

extension UnipolarValue {
  var isBeyondSleepDeadzone: Bool { normalized > controllerSleepTriggerDeadzone }
}
