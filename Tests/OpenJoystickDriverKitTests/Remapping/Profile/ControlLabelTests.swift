import Testing

@testable import OpenJoystickDriverKit

/// Pins the one table between remapping sources and controls, per label family.
struct ControlLabelTests {
  /// Every family, walked through an exhaustive switch, so a new family fails to compile until
  /// it is placed in the walk.
  static let families: [ControllerButtonLabels] = Array(
    sequence(first: ControllerButtonLabels.standard) { labels in
      switch labels {
      case .standard: .playStation
      case .playStation: .nintendo
      case .nintendo: nil
      }
    }
  )

  static func name(_ labels: ControllerButtonLabels) -> String {
    switch labels {
    case .standard: "standard"
    case .playStation: "playStation"
    case .nintendo: "nintendo"
    }
  }

  /// One line per source: the control it reads under standard, PlayStation and Nintendo labels.
  @Test
  func everySourceReadsItsFamilyControl() {
    let lines = RemappingButton.allCases.map { button in
      ([button.rawValue] + Self.families.map { button.controlID(labels: $0)?.rawValue ?? "-" })
        .joined(separator: " ")
    }
    #expect(
      lines == [
        "south face-south face-south face-south", "east face-east face-east face-east",
        "west face-west face-west face-west", "north face-north face-north face-north",
        "left_shoulder left-shoulder left-shoulder left-shoulder",
        "right_shoulder right-shoulder right-shoulder right-shoulder",
        "left_stick left-stick-click left-stick-click left-stick-click",
        "right_stick right-stick-click right-stick-click right-stick-click", "start menu - menu",
        "back view - view", "guide guide guide guide", "share share view capture",
        "options - menu -", "touchpad touchpad-click touchpad-click touchpad-click",
        "mute microphone microphone microphone",
        "left_trigger_click left-trigger-button left-trigger-button left-trigger-button",
        "right_trigger_click right-trigger-button right-trigger-button right-trigger-button",
        "left_grip paddle-left-2 paddle-left-2 paddle-left-2",
        "right_grip paddle-right-2 paddle-right-2 paddle-right-2",
        "left_pad_click left-trackpad-click left-trackpad-click left-trackpad-click",
        "right_pad_click right-trackpad-click right-trackpad-click right-trackpad-click",
        "left_sl auxiliary-3 auxiliary-3 auxiliary-3",
        "left_sr auxiliary-4 auxiliary-4 auxiliary-4",
        "right_sl auxiliary-5 auxiliary-5 auxiliary-5",
        "right_sr auxiliary-6 auxiliary-6 auxiliary-6",
        "left_function auxiliary-1 auxiliary-1 auxiliary-1",
        "right_function auxiliary-2 auxiliary-2 auxiliary-2",
        "left_paddle paddle-left-1 paddle-left-1 paddle-left-1",
        "right_paddle paddle-right-1 paddle-right-1 paddle-right-1",
      ]
    )
  }

  /// One line per control: the source that reads it under each family, `-` when none does.
  @Test
  func everyControlResolvesToAtMostOneSourcePerFamily() {
    let lines = ControlID.allCases.map { control in
      ([control.rawValue]
        + Self.families.map { RemappingButton(control: control, labels: $0)?.rawValue ?? "-" })
        .joined(separator: " ")
    }
    #expect(
      lines == [
        "dpad - - -", "left-stick-x - - -", "left-stick-y - - -", "right-stick-x - - -",
        "right-stick-y - - -", "left-stick-click left_stick left_stick left_stick",
        "right-stick-click right_stick right_stick right_stick", "face-south south south south",
        "face-east east east east", "face-west west west west", "face-north north north north",
        "left-shoulder left_shoulder left_shoulder left_shoulder",
        "right-shoulder right_shoulder right_shoulder right_shoulder", "left-trigger - - -",
        "right-trigger - - -",
        "left-trigger-button left_trigger_click left_trigger_click left_trigger_click",
        "right-trigger-button right_trigger_click right_trigger_click right_trigger_click",
        "view back share back", "menu start options start", "guide guide guide guide",
        "share share - -", "capture - - share", "touchpad-click touchpad touchpad touchpad",
        "microphone mute mute mute", "paddle-left-1 left_paddle left_paddle left_paddle",
        "paddle-left-2 left_grip left_grip left_grip",
        "paddle-right-1 right_paddle right_paddle right_paddle",
        "paddle-right-2 right_grip right_grip right_grip",
        "auxiliary-1 left_function left_function left_function",
        "auxiliary-2 right_function right_function right_function",
        "auxiliary-3 left_sl left_sl left_sl", "auxiliary-4 left_sr left_sr left_sr",
        "auxiliary-5 right_sl right_sl right_sl", "auxiliary-6 right_sr right_sr right_sr",
        "auxiliary-7 - - -", "auxiliary-8 - - -", "left-stick-touch - - -",
        "right-stick-touch - - -",
        "left-trackpad-click left_pad_click left_pad_click left_pad_click",
        "right-trackpad-click right_pad_click right_pad_click right_pad_click",
        "left-trackpad-touch - - -", "right-trackpad-touch - - -",
      ]
    )
  }

  @Test(arguments: families)
  func sourcesRoundTripThroughTheirControl(_ labels: ControllerButtonLabels) {
    for button in RemappingButton.allCases {
      guard let control = button.controlID(labels: labels) else { continue }
      #expect(
        RemappingButton(control: control, labels: labels) == button,
        "\(Self.name(labels)) \(button)"
      )
    }
  }

  @Test(arguments: families)
  func controlsRoundTripThroughTheirSource(_ labels: ControllerButtonLabels) {
    for control in ControlID.allCases {
      guard let button = RemappingButton(control: control, labels: labels) else { continue }
      #expect(button.controlID(labels: labels) == control, "\(Self.name(labels)) \(control)")
    }
  }

  @Test
  func axesReadTheirSameNamedControl() {
    #expect(
      RemappingAxis.allCases.map { "\($0.rawValue) \($0.controlID.rawValue)" } == [
        "left_stick_x left-stick-x", "left_stick_y left-stick-y", "right_stick_x right-stick-x",
        "right_stick_y right-stick-y", "left_trigger left-trigger", "right_trigger right-trigger",
      ]
    )
  }
}
