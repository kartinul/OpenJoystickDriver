import Foundation
import OpenJoystickDriverKit

enum RuntimePresentation {
  static func permissionLabel(_ state: RuntimePermissionState) -> String {
    switch state {
    case .granted: return OJDLocalized.string("status.allowed", fallback: "Allowed")
    case .denied: return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case .unknown: return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case .unavailable: return OJDLocalized.string("common.unavailable", fallback: "Unavailable")
    }
  }

  static func readinessLabel(_ readiness: RuntimeReadiness) -> String {
    switch readiness {
    case .ready: return OJDLocalized.string("status.ready", fallback: "Ready")
    case .needsAttention:
      return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case .noController:
      return OJDLocalized.string("status.connectController", fallback: "Connect a controller")
    }
  }

  static func postEventAccessLabel(_ state: RemappingPostEventAccessState?) -> String {
    switch state {
    case .granted: return OJDLocalized.string("status.allowed", fallback: "Allowed")
    case .notAuthorized:
      return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case nil: return OJDLocalized.string("status.checking", fallback: "Checking")
    }
  }

  static func deviceCountLabel(_ count: Int) -> String {
    OJDLocalized.plural(
      "status.controllerConnected",
      count: count,
      fallback: "%d controllers connected"
    )
  }

  static func profileLabel(_ profile: RemappingProfile) -> String { profile.name }

  static func profileScopeLabel(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: return OJDLocalized.string("mapping.allApps", fallback: "All apps")
    case .application: return OJDLocalized.string("mapping.specificApp", fallback: "A specific app")
    }
  }

  static var noVirtualHIDProfileLabel: String {
    OJDLocalized.string("virtualProfile.none", fallback: "No virtual HID profile")
  }

  /// The wire source of a virtual HID profile: `automatic`, `override`, or
  /// `automatic-after-rejecting`.
  static func virtualHIDProfileSourceLabel(_ source: String) -> String {
    switch source {
    case "automatic": return OJDLocalized.string("mapping.automatic", fallback: "Automatic")
    case "override":
      return OJDLocalized.string("virtualProfile.sourceOverride", fallback: "Override")
    case "automatic-after-rejecting":
      return OJDLocalized.string(
        "virtualProfile.sourceAutomaticAfterRejecting",
        fallback: "Automatic, override rejected"
      )
    default: return source
    }
  }

  /// A failed virtual HID profile override request. Says whether the override was stored.
  static func virtualHIDProfileOverrideFailure(
    _ failure: VirtualHIDProfileOverrideFailure
  ) -> String {
    switch failure {
    case .unknownProfile:
      return OJDLocalized.string(
        "virtualProfile.failure.unknownProfile",
        fallback: "This virtual HID profile is unknown. Nothing was stored."
      )
    case .controllerNotFound:
      return OJDLocalized.string(
        "virtualProfile.failure.controllerNotFound",
        fallback: "The controller disconnected or can't be found. The override is unchanged."
      )
    case .overrideRejectedByController:
      return OJDLocalized.string(
        "virtualProfile.failure.overrideRejected",
        fallback:
          "The override is stored, but this controller can't use it, so it selects automatically."
      )
    case .activationFailed(let detail):
      return OJDLocalized.formatted(
        "virtualProfile.failure.activationFailed",
        fallback: "Activation failed, so the previous virtual HID profile was restored: %@",
        detail
      )
    case .outputDisabled:
      return OJDLocalized.string(
        "virtualProfile.failure.outputDisabled",
        fallback: "The override is stored and applies once virtual output is enabled."
      )
    case .serverStopped:
      return OJDLocalized.string(
        "virtualProfile.failure.serverStopped",
        fallback: "The service stopped. The override is unchanged."
      )
    case .persistenceFailed:
      return OJDLocalized.string(
        "virtualProfile.failure.persistenceFailed",
        fallback: "The override couldn't be saved. Nothing was stored."
      )
    }
  }

  static func sourceLabel(_ source: RemappingSource) -> String {
    switch source {
    case .button(let button): return buttonLabel(button)
    case .dpad(let direction):
      return OJDLocalized.formatted(
        "mapping.dpadDirection",
        fallback: "D-pad %@",
        humanized(direction.rawValue)
      )
    case .axis(let axis): return axisLabel(axis)
    case .axisDirection(let axis, let direction):
      return OJDLocalized.formatted(
        "mapping.axisDirection",
        fallback: "%@ %@",
        axisLabel(axis),
        humanized(direction.rawValue)
      )
    case .triggerStage(let trigger, let stage):
      return OJDLocalized.formatted(
        "mapping.triggerStage",
        fallback: "%@ trigger %@ pull",
        humanized(trigger.rawValue),
        humanized(stage.rawValue)
      )
    case .motionLean(let direction):
      return OJDLocalized.formatted(
        "mapping.motionLean",
        fallback: "Motion lean %@",
        humanized(direction.rawValue)
      )
    case .touchContact(let surface):
      return OJDLocalized.formatted(
        "mapping.touchContact",
        fallback: "%@ touch",
        touchSurfaceLabel(surface)
      )
    case .touchGrid(let grid):
      return OJDLocalized.formatted(
        "mapping.touchGridCell",
        fallback: "%@ grid %d×%d cell %d,%d",
        touchSurfaceLabel(grid.surface),
        grid.columns,
        grid.rows,
        grid.column + 1,
        grid.row + 1
      )
    case .touchSwipe(let swipe):
      return OJDLocalized.formatted(
        "mapping.touchSwipe",
        fallback: "%@ swipe %@",
        touchSurfaceLabel(swipe.surface),
        humanized(swipe.direction.rawValue)
      )
    }
  }

  private static func touchSurfaceLabel(_ surface: RemappingTouchSurface) -> String {
    switch surface {
    case .primary: OJDLocalized.string("mapping.touchSurfacePrimary", fallback: "Primary surface")
    case .left: OJDLocalized.string("mapping.touchSurfaceLeft", fallback: "Left surface")
    case .right: OJDLocalized.string("mapping.touchSurfaceRight", fallback: "Right surface")
    }
  }

  static func destinationLabel(_ destination: RemappingDestination) -> String {
    switch destination {
    case .gamepadAxis(let axis): return axisLabel(axis)
    case .gamepadDpad(let direction): return sourceLabel(.dpad(direction))
    case .gamepadButton(let button): return buttonLabel(button)
    case .keyboard(let key, let modifiers):
      let modifierLabel = modifiers.sorted { $0.rawValue < $1.rawValue }.map(Self.modifierLabel)
        .joined(separator: " + ")
      let keyLabel = keyboardKeyLabel(key)
      return modifierLabel.isEmpty ? keyLabel : "\(modifierLabel) + \(keyLabel)"
    case .mouseButton(let button):
      return OJDLocalized.formatted(
        "mapping.mouseButton",
        fallback: "Mouse %@ button",
        humanized(button.rawValue)
      )
    case .mouseMovement(let axis):
      return OJDLocalized.formatted(
        "mapping.pointerMovement",
        fallback: "Pointer %@ movement",
        humanized(axis.rawValue)
      )
    case .scroll(let axis):
      return OJDLocalized.formatted(
        "mapping.scroll",
        fallback: "Scroll %@",
        humanized(axis.rawValue)
      )
    case .physical(let output): return physicalOutputLabel(output)
    }
  }

  static func physicalOutputLabel(_ output: RemappingPhysicalOutput) -> String {
    switch output {
    case .rumble(let motor, let intensity):
      return OJDLocalized.formatted(
        "mapping.physicalRumble",
        fallback: "%@ rumble (%@%%)",
        humanized(motor.rawValue),
        String(Int((intensity * 100).rounded()))
      )
    case .playerIndicator(let indicator):
      return OJDLocalized.formatted(
        "mapping.physicalPlayerIndicator",
        fallback: "Player indicator %@",
        indicator == .off
          ? OJDLocalized.string("common.disabled", fallback: "Disabled")
          : String(indicator.rawValue)
      )
    case .color(let red, let green, let blue):
      return OJDLocalized.formatted(
        "mapping.physicalColor",
        fallback: "Controller color %@",
        String(format: "#%02X%02X%02X", red, green, blue)
      )
    case .brightness(let intensity):
      return OJDLocalized.formatted(
        "mapping.physicalBrightness",
        fallback: "Controller brightness (%@%%)",
        String(Int((intensity * 100).rounded()))
      )
    case .adaptiveTrigger(let trigger, let effect):
      return OJDLocalized.formatted(
        "mapping.physicalAdaptiveTrigger",
        fallback: "%@ adaptive trigger: %@",
        humanized(trigger.rawValue),
        humanized(effect.kind.rawValue)
      )
    }
  }

  /// Buttons in capture priority order. Guide/Home/logo is reserved for the operating system and
  /// is intentionally excluded from automatic capture, just like the manual SourceOption catalog.
  private static let captureButtonOrder: [RemappingButton] = [
    .leftFunction, .rightFunction, .leftPaddle, .rightPaddle, .leftSL, .leftSR, .rightSL, .rightSR,
    .leftGrip, .rightGrip, .leftPadClick, .rightPadClick, .south, .east, .west, .north,
    .leftShoulder, .rightShoulder, .leftStick, .rightStick, .start, .back, .share, .options,
    .touchpad, .mute, .leftTriggerClick, .rightTriggerClick,
  ]

  static func detectedSource(
    from state: ControllerState,
    labels: ControllerButtonLabels
  ) -> RemappingSource? {
    if let sample = state.touch.first(where: { $0.contacts.contains(where: \.isActive) }) {
      return .touchContact(RemappingTouchSurface(sample.surface))
    }
    return detectedButton(pressed: state.pressed, dpad: dpadDirections(state.hat), labels: labels)
      ?? detectedAxis(in: state)
  }

  static func detectedTransition(
    from previous: ControllerState,
    to current: ControllerState,
    labels: ControllerButtonLabels
  ) -> RemappingSource? {
    let previousTouches = activeTouchSurfaces(previous)
    let currentTouches = activeTouchSurfaces(current)
    if let surface = RemappingTouchSurface.allCases.first(where: {
      currentTouches.contains($0) && !previousTouches.contains($0)
    }) {
      return .touchContact(surface)
    }
    if let source = detectedButton(
      pressed: current.pressed.subtracting(previous.pressed),
      dpad: dpadDirections(current.hat).subtracting(dpadDirections(previous.hat)),
      labels: labels
    ) {
      return source
    }
    let previousAxes = axisValues(previous)
    for (index, (currentValue, axis)) in axisValues(current).enumerated() {
      let previousValue = previousAxes[index].value
      let crossedActivation = abs(currentValue) >= 0.5 && abs(previousValue) < 0.5
      let changedDirection =
        abs(currentValue) >= 0.5 && abs(previousValue) >= 0.5
        && (previousValue < 0) != (currentValue < 0)
      guard crossedActivation || changedDirection else { continue }
      let direction: RemappingAxisDirection = currentValue < 0 ? .negative : .positive
      return .axisDirection(axis, direction)
    }

    // A source becoming unrecognized or disappearing is a release, not a new assignment.  Only
    // newly pressed controls and axis activation/direction transitions above count as input.
    return nil
  }

  private static func detectedButton(
    pressed: Set<ControlID>,
    dpad: Set<RemappingDpadDirection>,
    labels: ControllerButtonLabels
  ) -> RemappingSource? {
    if let button = captureButtonOrder.first(where: { button in
      button.controlID(labels: labels).map(pressed.contains) ?? false
    }) {
      return .button(button)
    }
    let order: [RemappingDpadDirection] = [.up, .down, .left, .right]
    return order.first(where: dpad.contains).map(RemappingSource.dpad)
  }

  private static func detectedAxis(in state: ControllerState) -> RemappingSource? {
    for (value, axis) in axisValues(state) where abs(value) >= 0.5 {
      let direction: RemappingAxisDirection = value < 0 ? .negative : .positive
      return .axisDirection(axis, direction)
    }
    return nil
  }

  /// Axis values in the remapping frame, where stick Y points down.
  private static func axisValues(_ state: ControllerState) -> [(value: Float, axis: RemappingAxis)]
  {
    [
      (state.leftStick.x.normalized, .leftStickX), (-state.leftStick.y.normalized, .leftStickY),
      (state.rightStick.x.normalized, .rightStickX), (-state.rightStick.y.normalized, .rightStickY),
      (state.leftTrigger.normalized, .leftTrigger), (state.rightTrigger.normalized, .rightTrigger),
    ]
  }

  private static func activeTouchSurfaces(_ state: ControllerState) -> Set<RemappingTouchSurface> {
    Set(
      state.touch.compactMap { sample in
        sample.contacts.contains(where: \.isActive) ? RemappingTouchSurface(sample.surface) : nil
      }
    )
  }

  static func dpadDirections(_ hat: HatDirection) -> Set<RemappingDpadDirection> {
    switch hat {
    case .neutral: []
    case .north: [.up]
    case .northEast: [.up, .right]
    case .east: [.right]
    case .southEast: [.down, .right]
    case .south: [.down]
    case .southWest: [.down, .left]
    case .west: [.left]
    case .northWest: [.up, .left]
    }
  }

}
