/// How a controller family labels the buttons around its guide button.
///
/// Parsers emit family labels (`Button.options` on PlayStation, `Button.share` for Nintendo
/// Capture), so the same remapping source names a different control per family.
public enum ControllerButtonLabels: Equatable, Sendable {
  case standard
  case playStation
  case nintendo

  public init(protocolID: PhysicalProtocolID) {
    switch protocolID {
    case .sonyDualShock4, .sonyDualSense: self = .playStation
    case .nintendoSwitch1: self = .nintendo
    default: self = .standard
    }
  }
}

/// Controller features that can be selected safely while editing a remapping profile.
public struct ControllerProfileCapabilities: Equatable, Sendable {
  public let physicalInput: ControllerCapabilities
  public let physicalOutput: PhysicalControllerOutputCapabilities
  public let buttonLabels: ControllerButtonLabels

  /// A device OJD cannot describe: every standard-labelled control stays selectable, without
  /// touch, motion or physical output.
  public static let unknown = Self(
    physicalInput: ControllerCapabilities(controls: Set(ControlID.allCases)),
    physicalOutput: .none,
    buttonLabels: .standard
  )

  public init(
    physicalInput: ControllerCapabilities,
    physicalOutput: PhysicalControllerOutputCapabilities,
    buttonLabels: ControllerButtonLabels
  ) {
    self.physicalInput = physicalInput
    self.physicalOutput = physicalOutput
    self.buttonLabels = buttonLabels
  }

  public var supportsStickAxes: Bool {
    !physicalInput.controls.isDisjoint(with: [.leftStickX, .leftStickY, .rightStickX, .rightStickY])
  }

  public var supportsAnalogTriggers: Bool {
    !physicalInput.controls.isDisjoint(with: [.leftTrigger, .rightTrigger])
  }

  public func intersecting(_ other: Self) -> Self {
    Self(
      physicalInput: physicalInput.intersecting(other.physicalInput),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: intersection(physicalOutput.rumbleMotors, other.physicalOutput.rumbleMotors),
        lightingFeatures: intersection(
          physicalOutput.lightingFeatures,
          other.physicalOutput.lightingFeatures
        ),
        binaryRumbleMotors: intersection(
          physicalOutput.binaryRumbleMotors,
          other.physicalOutput.binaryRumbleMotors
        ),
        adaptiveTriggers: intersection(
          physicalOutput.adaptiveTriggers,
          other.physicalOutput.adaptiveTriggers
        )
      ),
      buttonLabels: buttonLabels
    )
  }
}

private func intersection<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> [Element] {
  lhs.filter(rhs.contains)
}
