#if canImport(SwiftUI)

  import OpenJoystickDriverKit

  enum InputTestButtonPresentation {
    /// Controls the live input view draws in its own clusters under every label set; the view
    /// slot's controls depend on the labels.
    static let drawnControls: Set<ControlID> = [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder,
      .leftTriggerButton, .rightTriggerButton, .menu, .guide, .leftStickClick, .rightStickClick,
    ]

    /// The core face, shoulder, stick and system set; Share, Capture, Mute, touchpad and paddles
    /// surface as extras in Developer Tools.
    static let coreDiagnosticControls = drawnControls.union([.view])

    /// Pressed controls no cluster draws, such as Share and Capture, in `ControlID` order.
    static func additionalControls(
      in state: ControllerState,
      labels: ControllerButtonLabels
    ) -> [ControlID] {
      let drawn = drawnControls.union(InputTestSystemClusterLayout.viewControls(labels: labels))
      return ControlID.allCases.filter { state.pressed.contains($0) && !drawn.contains($0) }
    }

    /// The remapping source name of `control` under the controller's labels, else its ID.
    static func localizedTitle(for control: ControlID, labels: ControllerButtonLabels) -> String {
      guard let button = RemappingButton(control: control, labels: labels) else {
        return control.rawValue
      }
      return RuntimePresentation.sourceLabel(.button(button))
    }
  }

#endif
