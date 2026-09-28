import Foundation

/// The one trigger-button policy for protocols without a distinct digital trigger signal.
///
/// A driver whose protocol reports a physical digital trigger declares `leftTriggerButton` or
/// `rightTriggerButton` in its capabilities and emits it from that signal. For a side whose driver
/// declares only the analog trigger, normalization derives the button from the canonical analog
/// value: it presses at `pressThreshold` and, once pressed, releases only at or below
/// `releaseThreshold`. The values reuse the remapping defaults for an axis acting as a button,
/// applied here to the canonical value with no dead zone. A remapped trigger axis sets the virtual
/// digital trigger by the same rule.
enum TriggerButtonDerivation {
  static let pressThreshold = UnipolarValue(
    normalized: Float(RemappingAxisTuning.defaultDigitalActivationThreshold)
  )
  static let releaseThreshold = UnipolarValue(
    normalized: Float(
      RemappingAxisTuning.defaultDigitalActivationThreshold - RemappingTransform.hysteresisWidth
    )
  )

  /// The trigger sides `capabilities` leaves to derivation: an analog trigger with no declared
  /// digital trigger button.
  static func derivedSides(
    of capabilities: ControllerCapabilities
  ) -> [(trigger: KeyPath<ControllerState, UnipolarValue>, button: ControlID)] {
    [
      (\ControllerState.leftTrigger, ControlID.leftTrigger, ControlID.leftTriggerButton),
      (\ControllerState.rightTrigger, .rightTrigger, .rightTriggerButton),
    ].compactMap { trigger, analog, button in
      capabilities.controls.contains(analog) && !capabilities.controls.contains(button)
        ? (trigger, button) : nil
    }
  }

  /// `state` with each derived trigger button set from its analog trigger; `previous` is the last
  /// normalized state, whose derived button decides which threshold applies.
  static func applying(
    to state: ControllerState,
    previous: ControllerState,
    capabilities: ControllerCapabilities
  ) -> ControllerState {
    var next = state
    for (trigger, button) in derivedSides(of: capabilities) {
      next.set(
        button,
        pressed: isPressed(state[keyPath: trigger], wasPressed: previous.pressed.contains(button))
      )
    }
    return next
  }

  /// Whether a trigger at `value` reads as pressed, given whether it read as pressed before.
  static func isPressed(_ value: UnipolarValue, wasPressed: Bool) -> Bool {
    wasPressed
      ? value.rawValue > releaseThreshold.rawValue : value.rawValue >= pressThreshold.rawValue
  }
}

extension ControllerCapabilities {
  /// The capabilities after normalization: the declared controls plus each trigger button
  /// normalization derives.
  public var normalized: ControllerCapabilities {
    let derived = TriggerButtonDerivation.derivedSides(of: self).map(\.button)
    guard !derived.isEmpty else { return self }
    return ControllerCapabilities(
      controls: controls.union(derived),
      touchContactCount: touchContactCount,
      motion: motion
    )
  }
}
