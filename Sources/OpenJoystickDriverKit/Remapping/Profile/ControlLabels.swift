import Foundation

/// The one table between remapping sources and semantic controls.
///
/// Parsers emit family labels, so the engine keys a button source by that label: PlayStation reads
/// Options as Menu and Share as View and never reports Start or Back; Nintendo reads Share as
/// Capture; the other families never report Options.
extension RemappingButton {
  /// The control this source reads under `labels`, or nil when that family never reports it.
  public func controlID(labels: ControllerButtonLabels) -> ControlID? {
    // Each label-sensitive source switches over every family, so a new family must choose.
    switch self {
    case .start:
      switch labels {
      case .standard, .nintendo: return .menu
      case .playStation: return nil
      }
    case .back:
      switch labels {
      case .standard, .nintendo: return .view
      case .playStation: return nil
      }
    case .options:
      switch labels {
      case .playStation: return .menu
      case .standard, .nintendo: return nil
      }
    case .share:
      switch labels {
      case .standard: return .share
      case .playStation: return .view
      case .nintendo: return .capture
      }
    default: return familyIndependentControlID
    }
  }

  /// The source that reads `control` under `labels`, or nil when no source reads it.
  public init?(control: ControlID, labels: ControllerButtonLabels) {
    let sources =
      switch labels {
      case .standard: Self.standardSources
      case .playStation: Self.playStationSources
      case .nintendo: Self.nintendoSources
      }
    guard let button = sources[control] else { return nil }
    self = button
  }

  private static let standardSources = sources(labels: .standard)
  private static let playStationSources = sources(labels: .playStation)
  private static let nintendoSources = sources(labels: .nintendo)

  /// The first source in declaration order that reads each control under `labels`.
  private static func sources(labels: ControllerButtonLabels) -> [ControlID: RemappingButton] {
    var sources: [ControlID: RemappingButton] = [:]
    for button in allCases {
      guard let control = button.controlID(labels: labels), sources[control] == nil else {
        continue
      }
      sources[control] = button
    }
    return sources
  }

  private var familyIndependentControlID: ControlID {
    switch self {
    case .south: return .faceSouth
    case .east: return .faceEast
    case .west: return .faceWest
    case .north: return .faceNorth
    case .leftShoulder: return .leftShoulder
    case .rightShoulder: return .rightShoulder
    case .leftStick: return .leftStickClick
    case .rightStick: return .rightStickClick
    case .start, .options: return .menu
    case .back: return .view
    case .guide: return .guide
    case .share: return .share
    case .touchpad: return .touchpadClick
    case .mute: return .microphone
    case .leftTriggerClick: return .leftTriggerButton
    case .rightTriggerClick: return .rightTriggerButton
    case .leftGrip: return .paddleLeft2
    case .rightGrip: return .paddleRight2
    case .leftPadClick: return .leftTrackpadClick
    case .rightPadClick: return .rightTrackpadClick
    case .leftSL: return .auxiliary3
    case .leftSR: return .auxiliary4
    case .rightSL: return .auxiliary5
    case .rightSR: return .auxiliary6
    case .leftFunction: return .auxiliary1
    case .rightFunction: return .auxiliary2
    case .leftPaddle: return .paddleLeft1
    case .rightPaddle: return .paddleRight1
    }
  }
}

extension RemappingAxis {
  /// The control this axis source reads; axes carry no family labels.
  public var controlID: ControlID {
    switch self {
    case .leftStickX: return .leftStickX
    case .leftStickY: return .leftStickY
    case .rightStickX: return .rightStickX
    case .rightStickY: return .rightStickY
    case .leftTrigger: return .leftTrigger
    case .rightTrigger: return .rightTrigger
    }
  }
}
