import Testing

@testable import OpenJoystickDriverKit

// Pinned compatibility-path transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Every former parser button pressed and released alone, in its former declaration order: the
  /// control it reported under the family that spelled it, and a d-pad button as its hat direction.
  @Test
  func everyButtonPressAndRelease() async {
    var lines: [String] = []
    let output = VirtualOutput()
    for (name, press, release, labels) in Self.formerParserButtons {
      await output.dispatch([press], from: Self.standard, labels: labels)
      lines += output.render("+\(name)")
      await output.dispatch([release], from: Self.standard, labels: labels)
      lines += output.render("-\(name)")
    }
    #expect(
      lines == [
        "+a b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0100000000000000000000000000",
        "-a b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+b b=0002 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0200000000000000000000000000",
        "-b b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+x b=0004 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0400000000000000000000000000",
        "-x b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+y b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0800000000000000000000000000",
        "-y b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+leftBumper b=0010 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 1000000000000000000000000000",
        "-leftBumper b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+rightBumper b=0020 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 2000000000000000000000000000",
        "-rightBumper b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+leftStick b=0040 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0001000000000000000000000000",
        "-leftStick b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+rightStick b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0002000000000000000000000000",
        "-rightStick b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+start b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 8000000000000000000000000000",
        "-start b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+back b=0200 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 4000000000000000000000000000",
        "-back b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+guide b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "-guide b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+dpadUp b=0800 h=1 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0004000000000000000000000000",
        "-dpadUp b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+dpadDown b=1000 h=5 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0008000000000000000000000000",
        "-dpadDown b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+dpadLeft b=2000 h=7 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0010000000000000000000000000",
        "-dpadLeft b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+dpadRight b=4000 h=3 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0020000000000000000000000000",
        "-dpadRight b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+cross b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0100000000000000000000000000",
        "-cross b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+circle b=0002 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0200000000000000000000000000",
        "-circle b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+square b=0004 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0400000000000000000000000000",
        "-square b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+triangle b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0800000000000000000000000000",
        "-triangle b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+l1 b=0010 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 1000000000000000000000000000",
        "-l1 b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+r1 b=0020 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 2000000000000000000000000000",
        "-r1 b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+l2Digital b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=10 +1", "  out 00000000000000000000ff7f0000",
        "-l2Digital b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+r2Digital b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=01 +1", "  out 000000000000000000000000ff7f",
        "-r2Digital b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+share b=8000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0080000000000000000000000000",
        "-share b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+options b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 8000000000000000000000000000",
        "-options b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+ps b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "-ps b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+touchpad b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-touchpad b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+mute b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-mute b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+leftGrip b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-leftGrip b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+rightGrip b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-rightGrip b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+leftPadClick b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-leftPadClick b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+rightPadClick b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0002000000000000000000000000",
        "-rightPadClick b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "+leftSL b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-leftSL b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+leftSR b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-leftSR b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+rightSL b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-rightSL b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+rightSR b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-rightSR b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+leftFunction b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-leftFunction b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+rightFunction b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-rightFunction b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+leftPaddle b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-leftPaddle b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "+rightPaddle b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
        "-rightPaddle b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
      ]
    )
  }

  /// The former parser buttons in declaration order, as the snapshot change each reported.
  static let formerParserButtons: [(String, InputChange, InputChange, ControllerButtonLabels)] =
    [
      ("a", ControlID.faceSouth, ControllerButtonLabels.standard), ("b", .faceEast, .standard),
      ("x", .faceWest, .standard), ("y", .faceNorth, .standard),
      ("leftBumper", .leftShoulder, .standard), ("rightBumper", .rightShoulder, .standard),
      ("leftStick", .leftStickClick, .standard), ("rightStick", .rightStickClick, .standard),
      ("start", .menu, .standard), ("back", .view, .standard), ("guide", .guide, .standard),
    ].map { ($0.0, InputChange.press($0.1), InputChange.release($0.1), $0.2) }
    + [
      ("dpadUp", HatDirection.north), ("dpadDown", .south), ("dpadLeft", .west),
      ("dpadRight", .east),
    ].map {
      ($0.0, InputChange.hat($0.1), InputChange.hat(.neutral), ControllerButtonLabels.standard)
    }
    + [
      ("cross", ControlID.faceSouth, ControllerButtonLabels.playStation),
      ("circle", .faceEast, .playStation), ("square", .faceWest, .playStation),
      ("triangle", .faceNorth, .playStation), ("l1", .leftShoulder, .playStation),
      ("r1", .rightShoulder, .playStation), ("l2Digital", .leftTriggerButton, .playStation),
      ("r2Digital", .rightTriggerButton, .playStation), ("share", .share, .standard),
      ("options", .menu, .playStation), ("ps", .guide, .playStation),
      ("touchpad", .touchpadClick, .playStation), ("mute", .microphone, .playStation),
      ("leftGrip", .paddleLeft2, .standard), ("rightGrip", .paddleRight2, .standard),
      ("leftPadClick", .leftTrackpadClick, .standard),
      ("rightPadClick", .rightTrackpadClick, .standard), ("leftSL", .auxiliary3, .nintendo),
      ("leftSR", .auxiliary4, .nintendo), ("rightSL", .auxiliary5, .nintendo),
      ("rightSR", .auxiliary6, .nintendo), ("leftFunction", .auxiliary1, .playStation),
      ("rightFunction", .auxiliary2, .playStation), ("leftPaddle", .paddleLeft1, .playStation),
      ("rightPaddle", .paddleRight1, .playStation),
    ].map { ($0.0, InputChange.press($0.1), InputChange.release($0.1), $0.2) }
}
