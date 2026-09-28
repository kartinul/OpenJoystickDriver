import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Pinned remapped-path transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Mapped output emits only the bound destination; an unbound press emits nothing.
  @Test
  func buttonToButton() async throws {
    let session = EngineSession(
      Self.profile(
        .mapped,
        bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
      )
    )
    var lines = try await session.step("+a", [.press(.faceSouth)])
    lines += try await session.step("+b", [.press(.faceEast)])
    lines += try await session.step("-a", [.release(.faceSouth)])
    lines += try await session.step("+a", [.press(.faceSouth)])
    try await session.engine.releaseAll(for: Self.engineDevice)
    lines += session.recorder.take("release-all")
    #expect(
      lines == [
        "+a", "  pad [north] d=[] a=[]", "    b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0800000000000000000000000000", "+b", "-a", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000", "+a",
        "  pad [north] d=[] a=[]", "    b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0800000000000000000000000000", "release-all", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }

  /// A keyboard destination with modifiers orders modifiers around the key.
  @Test
  func buttonToKey() async throws {
    let session = EngineSession(
      Self.profile(
        .disabled,
        bindings: [
          RemappingBinding(source: .button(.south), destination: Self.key(.c, [.command, .shift]))
        ]
      )
    )
    var lines = try await session.step("+a", [.press(.faceSouth)])
    lines += try await session.step("-a", [.release(.faceSouth)])
    #expect(
      lines == [
        "+a", "  sys modifier-down command", "  sys modifier-down shift", "  sys key-down c", "-a",
        "  sys key-up c", "  sys modifier-up shift", "  sys modifier-up command",
      ]
    )
  }

  /// A stick axis bound to another stick axis, through the default axis tuning.
  @Test
  func axisToAxis() async throws {
    let session = EngineSession(
      Self.profile(
        .mapped,
        bindings: [
          RemappingBinding(
            source: .axis(.leftStickX),
            destination: .gamepadAxis(.rightStickX),
            axisTuning: .default
          )
        ]
      )
    )
    var lines = try await session.step("ls.5", [.leftStick(x: 0.5, y: 0.25)])
    lines += try await session.step("ls-1", [.leftStick(x: -1, y: 0.25)])
    lines += try await session.step("ls.05", [.leftStick(x: 0.05, y: 0)])
    lines += try await session.step("ls0", [.leftStick(x: 0, y: 0)])
    #expect(
      lines == [
        "ls.5", "  pad [] d=[] a=[right_stick_x=14563]",
        "    b=0000 h=0 ls=0,0 rs=14562,0 t=0,0 f=00 +1", "  out 000000000000e238000000000000",
        "ls-1", "  pad [] d=[] a=[right_stick_x=-32767]",
        "    b=0000 h=0 ls=0,0 rs=-32767,0 t=0,0 f=00 +1", "  out 0000000000000180000000000000",
        "ls.05", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "ls0",
      ]
    )
  }

  /// A simultaneous chord (south+east → c) and a sequence (south, north → d) with their timing.
  @Test
  func chordAndSequence() async throws {
    let session = EngineSession(
      Self.profile(
        .disabled,
        chords: [
          RemappingChord(
            sources: [.button(.south), .button(.east)],
            destination: Self.key(.c),
            mode: .simultaneous,
            windowMs: 50
          )
        ],
        sequences: [
          RemappingSequence(
            sources: [.button(.south), .button(.north)],
            windowMs: 200,
            destination: Self.key(.d)
          )
        ]
      )
    )
    let ms: UInt64 = 1_000_000
    var lines = try await session.step("+a@0", [.press(.faceSouth)], at: 0)
    lines += try await session.step("+b@10", [.press(.faceEast)], at: 10 * ms)
    lines += try await session.step(
      "-a-b@20",
      [.release(.faceSouth), .release(.faceEast)],
      at: 20 * ms
    )
    lines += try await session.step("+a@1000", [.press(.faceSouth)], at: 1_000 * ms)
    lines += try await session.tick("tick@1100", at: 1_100 * ms)
    lines += try await session.step("-a@1110", [.release(.faceSouth)], at: 1_110 * ms)
    lines += try await session.step("+y@1120", [.press(.faceNorth)], at: 1_120 * ms)
    lines += try await session.tick("tick@1500", at: 1_500 * ms)
    lines += try await session.step("-y@1510", [.release(.faceNorth)], at: 1_510 * ms)
    lines += try await session.tick("tick@2000", at: 2_000 * ms)
    #expect(
      lines == [
        "+a@0", "+b@10", "  sys key-down c", "-a-b@20", "  sys key-up c", "+a@1000", "tick@1100",
        "-a@1110", "+y@1120", "  sys key-down d", "  sys key-up d", "tick@1500", "-y@1510",
        "tick@2000",
      ]
    )
  }

  /// Passthrough carries family labels as engine sources. A real DualSense report drives the
  /// PlayStation family: Create reaches Share (bit 15, not View bit 9), Options reaches Start, PS
  /// reaches Guide. Standard View, Menu, Guide and the right pad click follow as parser events.
  @Test
  func passthroughFamilyLabels() async throws {
    let playStation = EngineSession(Self.profile(.passthrough), device: Self.playStation)
    let driver = DualSenseDriver()
    var previous = ControllerState.neutral
    var lines: [String] = []
    for (label, offset, mask): (String, Int, UInt8) in [
      ("create", 9, 0x10), ("options", 9, 0x20), ("ps", 10, 0x01), ("neutral", 0, 0),
    ] {
      var report = [UInt8](repeating: 0, count: 64)
      report[0] = 0x01
      for index in 1...4 { report[index] = 128 }
      report[8] = 0x08
      if mask != 0 { report[offset] |= mask }
      let event = try #require(try driver.parseReport(Data(report)))
      let parsed = Self.renderChanges(from: previous, to: event, labels: .playStation)
      previous = event.state
      lines += try await playStation.step("ds \(label) [\(parsed)]", event: event)
    }
    let standard = EngineSession(Self.profile(.passthrough), device: Self.standard)
    for (button, control) in [
      ("back", ControlID.view), ("start", .menu), ("guide", .guide),
      ("rightPadClick", .rightTrackpadClick),
    ] {
      lines += try await standard.step("+\(button)", [.press(control)])
      lines += try await standard.step("-\(button)", [.release(control)])
    }
    #expect(
      lines == [
        "ds create [+share motion touch]", "  pad [share] d=[] a=[]",
        "    b=8000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0080000000000000000000000000",
        "ds options [-share +options motion touch]", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "  pad [options] d=[] a=[]", "    b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 8000000000000000000000000000", "ds ps [-options +guide motion touch]",
        "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "  pad [guide] d=[] a=[]",
        "    b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0040000000000000000000000000",
        "ds neutral [-guide motion touch]", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000", "+back",
        "  pad [back] d=[] a=[]", "    b=0200 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 4000000000000000000000000000", "-back", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+start", "  pad [start] d=[] a=[]", "    b=0100 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 8000000000000000000000000000", "-start", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+guide", "  pad [guide] d=[] a=[]", "    b=0400 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0040000000000000000000000000", "-guide", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "+rightPadClick", "  pad [right_stick] d=[] a=[]",
        "    b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0002000000000000000000000000",
        "-rightPadClick", "  pad [] d=[] a=[]", "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000",
      ]
    )
  }

  /// The engine emits one state per event of a batch, so a batch's intermediate states reach the
  /// virtual device; aliases stay held while either source is active.
  @Test
  func twoControlsInOneRemappedBatch() async throws {
    let session = EngineSession(Self.profile(.passthrough))
    let steps: [(String, [InputChange])] = [
      ("+b", [.press(.faceEast)]), ("+a-b", [.press(.faceSouth), .release(.faceEast)]),
      ("+x+y", [.press(.faceWest), .press(.faceNorth)]),
      ("-a-x-y", [.release(.faceSouth), .release(.faceWest), .release(.faceNorth)]),
      ("+a-a", [.press(.faceSouth), .release(.faceSouth)]), ("+rs", [.press(.rightStickClick)]),
      ("+rpc-rpc", [.press(.rightTrackpadClick), .release(.rightTrackpadClick)]),
      ("-rs", [.release(.rightStickClick)]),
    ]
    var lines: [String] = []
    for (label, events) in steps { lines += try await session.step(label, events) }
    #expect(
      lines == [
        "+b", "  pad [east] d=[] a=[]", "    b=0002 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0200000000000000000000000000", "+a-b", "  pad [east,south] d=[] a=[]",
        "    b=0003 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0300000000000000000000000000",
        "  pad [south] d=[] a=[]", "    b=0001 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0100000000000000000000000000", "+x+y", "  pad [south,west] d=[] a=[]",
        "    b=0005 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0500000000000000000000000000",
        "  pad [north,south,west] d=[] a=[]", "    b=000d h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0d00000000000000000000000000", "-a-x-y", "  pad [north,west] d=[] a=[]",
        "    b=000c h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0c00000000000000000000000000",
        "  pad [north] d=[] a=[]", "    b=0008 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0800000000000000000000000000", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000", "+a-a",
        "+rs", "  pad [right_stick] d=[] a=[]", "    b=0080 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0002000000000000000000000000", "+rpc-rpc", "-rs", "  pad [] d=[] a=[]",
        "    b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }

  /// Keyboard destinations of one batch follow the batch's event order.
  @Test
  func twoKeysInOneBatch() async throws {
    let session = EngineSession(
      Self.profile(
        .disabled,
        bindings: [
          RemappingBinding(source: .button(.south), destination: Self.key(.x)),
          RemappingBinding(source: .button(.east), destination: Self.key(.y)),
        ]
      )
    )
    var lines = try await session.step("+b", [.press(.faceEast)])
    lines += try await session.step("+a-b", [.press(.faceSouth), .release(.faceEast)])
    lines += try await session.step("-a+b", [.release(.faceSouth), .press(.faceEast)])
    lines += try await session.step("+a", [.press(.faceSouth)])
    #expect(
      lines == [
        "+b", "  sys key-down y", "+a-b", "  sys key-down x", "  sys key-up y", "-a+b",
        "  sys key-up x", "  sys key-down y", "+a", "  sys key-down x",
      ]
    )
  }
}
