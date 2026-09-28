import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

// Pinned Joy-Con pair transcripts; the rendering rules are on `JoyConPairCharacterizationTests`.
extension JoyConPairCharacterizationTests {
  /// The left half holds SL (bound to L), ZL, Minus, d-pad up and its stick while the right half
  /// taps buttons and moves its stick: no right-half step releases a left-half control.
  @Test
  func rightHalfNeverReleasesTheLeftHalf() async throws {
    let session = try await pairedSession()
    defer { session.harness.removeFiles() }
    let held: UInt32 = 0x20_0000 | 0x80_0000 | 0x100 | 0x2_0000
    let lines = try await session.run([
      Step(Self.left, held, stick: (4095, 2048)), Step(Self.right, 0x4), Step(Self.right, 0),
      Step(Self.right, 0x8 | 0x1), Step(Self.right, 0x1), Step(Self.right, 0),
      Step(Self.right, 0x40 | 0x80 | 0x200 | 0x1000), Step(Self.right, 0),
      Step(Self.right, 0, stick: (2048, 0)), Step(Self.right, 0), Step(Self.left, 0),
    ])
    #expect(
      lines == [
        "L a20100 4095,2048 [+back +left_trigger_click +left_sl hat=north ls=32767,0]",
        "  pad L +back", "  pad L +left_trigger_click", "  pad L +left_shoulder", "  pad L d+up",
        "  pad L left_stick_x=32767", "R 4 2048,2048 [+south]", "  pad L +south",
        "R 0 2048,2048 [-south]", "  pad L -south", "R 9 2048,2048 [+east +west]", "  pad L +east",
        "  pad L +west", "R 1 2048,2048 [-east]", "  pad L -east", "R 0 2048,2048 [-west]",
        "  pad L -west", "R 12c0 2048,2048 [+right_shoulder +start +guide +right_trigger_click]",
        "  pad L +right_shoulder", "  pad L +start", "  pad L +guide",
        "  pad L +right_trigger_click",
        "R 0 2048,2048 [-right_shoulder -start -guide -right_trigger_click]",
        "  pad L -right_shoulder", "  pad L -start", "  pad L -guide",
        "  pad L -right_trigger_click", "R 0 2048,0 [rs=0,32767]", "  pad L right_stick_y=32767",
        "R 0 2048,2048 [rs=0,0]", "  pad L right_stick_y=0",
        "L 0 2048,2048 [-back -left_trigger_click -left_sl hat=neutral ls=0,0]", "  pad L -back",
        "  pad L -left_trigger_click", "  pad L -left_shoulder", "  pad L d-up",
        "  pad L left_stick_x=0",
      ]
    )
  }

  /// The reverse: the right half holds A, R, Plus and its stick while the left half taps.
  @Test
  func leftHalfNeverReleasesTheRightHalf() async throws {
    let session = try await pairedSession()
    defer { session.harness.removeFiles() }
    let held: UInt32 = 0x4 | 0x40 | 0x200
    let lines = try await session.run([
      Step(Self.right, held, stick: (0, 2048)), Step(Self.left, 0x20_0000), Step(Self.left, 0),
      Step(Self.left, 0x2_0000 | 0x100), Step(Self.left, 0x100), Step(Self.left, 0),
      Step(Self.left, 0x40_0000 | 0x2000 | 0x800), Step(Self.left, 0),
      Step(Self.left, 0, stick: (2048, 4095)), Step(Self.left, 0), Step(Self.right, 0),
    ])
    #expect(
      lines == [
        "R 244 0,2048 [+south +right_shoulder +start rs=-32767,0]", "  pad L +south",
        "  pad L +right_shoulder", "  pad L +start", "  pad L right_stick_x=-32767",
        "L 200000 2048,2048 [+left_sl]", "  pad L +left_shoulder", "L 0 2048,2048 [-left_sl]",
        "  pad L -left_shoulder", "L 20100 2048,2048 [+back hat=north]", "  pad L +back",
        "  pad L d+up", "L 100 2048,2048 [hat=neutral]", "  pad L d-up", "L 0 2048,2048 [-back]",
        "  pad L -back", "L 402800 2048,2048 [+left_shoulder +left_stick +share]",
        "  pad L +left_shoulder", "  pad L +left_stick", "  pad L +share",
        "L 0 2048,2048 [-left_shoulder -left_stick -share]", "  pad L -left_shoulder",
        "  pad L -left_stick", "  pad L -share", "L 0 2048,4095 [ls=0,-32767]",
        "  pad L left_stick_y=-32767", "L 0 2048,2048 [ls=0,0]", "  pad L left_stick_y=0",
        "R 0 2048,2048 [-south -right_shoulder -start rs=0,0]", "  pad L -south",
        "  pad L -right_shoulder", "  pad L -start", "  pad L right_stick_x=0",
      ]
    )
  }

  /// Stopping the right half ends the pair: the shared device releases everything, including the
  /// left half's held controls, and the left half returns to compatibility output.
  @Test
  func stoppingOneHalfReleasesThePair() async throws {
    let session = try await pairedSession()
    defer { session.harness.removeFiles() }
    var lines = try await session.run([
      Step(Self.left, 0x20_0000 | 0x2_0000), Step(Self.right, 0x4),
    ])
    session.harness.recorder.removeAll()
    try await session.harness.router.stopController(Self.right)
    lines.append("stop R")
    lines += session.traces()
    lines += try await session.run([Step(Self.left, 0)])
    #expect(
      lines == [
        "L 220000 2048,2048 [+left_sl hat=north]", "  pad L +left_shoulder", "  pad L d+up",
        "R 4 2048,2048 [+south]", "  pad L +south", "stop R", "  pad L -left_shoulder",
        "  pad L -south d-up", "  compat-stop L", "L 0 2048,2048 [-left_sl hat=neutral]",
        "  compat L [neutral]",
      ]
    )
  }

  /// Both halves drive one destination: right SL is bound to L while the left half holds L. The
  /// right half's tap and release leave the left half's L held.
  @Test
  func bothHalvesDriveOneDestination() async throws {
    let session = try await pairedSession(bindings: [
      RemappingBinding(source: .button(.rightSL), destination: .gamepadButton(.leftShoulder))
    ])
    defer { session.harness.removeFiles() }
    let lines = try await session.run([
      Step(Self.left, 0x40_0000), Step(Self.right, 0x20), Step(Self.right, 0),
      Step(Self.right, 0x20), Step(Self.left, 0), Step(Self.right, 0),
    ])
    #expect(
      lines == [
        "L 400000 2048,2048 [+left_shoulder]", "  pad L +left_shoulder",
        "R 20 2048,2048 [+right_sl]", "R 0 2048,2048 [-right_sl]", "R 20 2048,2048 [+right_sl]",
        "L 0 2048,2048 [-left_shoulder]", "R 0 2048,2048 [-right_sl]", "  pad L -left_shoulder",
      ]
    )
  }
}
