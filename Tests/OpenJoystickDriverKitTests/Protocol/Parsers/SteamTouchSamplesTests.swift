import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SteamTouchSamplesTests {
  private func packet(counter: UInt8, flags: UInt8, x: Int16, y: Int16) -> Data {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 1
    bytes[2] = 1
    bytes[3] = 60
    bytes[4] = counter
    bytes[10] = flags
    for (offset, value) in [(16, x), (18, y), (20, Int16(-123)), (22, Int16(456))] {
      bytes[offset] = UInt8(truncatingIfNeeded: value)
      bytes[offset + 1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: value) >> 8)
    }
    return Data(bytes)
  }

  private func touches(_ event: ControllerEvent?) -> [ControllerTouchSample] {
    event?.touchFrames ?? []
  }

  @Test
  func independentPadsNormalizeEdgesWithTopAtZeroAndReleaseFrames() throws {
    let parser = SteamControllerDriver()
    let events = try parser.parseReport(packet(counter: 1, flags: 0x18, x: -32_768, y: 32_767))
    let frames = touches(events)
    try #require(frames.count == 2)
    #expect(frames.map(\.surface) == [.left, .right])
    // Raw left edge -32768 is X 0; raw Y grows upward, so the top edge 32767 is Y 0.
    #expect(frames[0].contacts == [ControllerTouchContact(slot: 0, isActive: true, x: 0, y: 0)])
    // Raw (-123, 456): X 32768 - 123, Y 65535 - (456 + 32768).
    #expect(
      frames[1].contacts == [ControllerTouchContact(slot: 0, isActive: true, x: 32_645, y: 32_311)]
    )
    #expect(frames[0].timestamp == events?.motion.first?.timestamp.monotonic)
    #expect(frames.allSatisfy { $0.timestamp == frames[0].timestamp })
    let far = touches(
      try parser.parseReport(packet(counter: 9, flags: 0x08, x: 32_767, y: -32_768))
    )
    #expect(
      far.first?.contacts == [ControllerTouchContact(slot: 0, isActive: true, x: 65_535, y: 65_535)]
    )
    let centre = touches(try parser.parseReport(packet(counter: 10, flags: 0x08, x: 0, y: 0)))
    #expect(
      centre.first?.contacts == [
        ControllerTouchContact(slot: 0, isActive: true, x: 32_768, y: 32_767)
      ]
    )
    let decoded = try JSONDecoder().decode(
      [ControllerTouchSample].self,
      from: JSONEncoder().encode(frames)
    )
    #expect(decoded == frames)
    let released = touches(try parser.parseReport(packet(counter: 2, flags: 0, x: 0, y: 0)))
    #expect(released.count == 2)
    #expect(released.allSatisfy { !$0.contacts[0].isActive })
  }

  @Test
  func interleavedPadAndStickPacketsDoNotOverwriteEachOther() throws {
    let parser = SteamControllerDriver()
    _ = try parser.parseReport(packet(counter: 1, flags: 0, x: 16_384, y: 0))
    let pad = try parser.parseReport(packet(counter: 2, flags: 0x88, x: -12_000, y: 8000))
    let held = StickPosition(x: BipolarValue(normalized: Float(16_384) / 32_767), y: .center)
    #expect(pad?.state.leftStick == held)
    let stick = try parser.parseReport(packet(counter: 3, flags: 0x80, x: 20_000, y: 0))
    let left = try #require(touches(stick).first)
    #expect(left.contacts[0].isActive)
    #expect(left.contacts[0].x == 20_768 && left.contacts[0].y == 24_767)
    #expect(stick?.state.leftStick != held)
    let padOnly = try parser.parseReport(packet(counter: 4, flags: 8, x: 100, y: 200))
    #expect(padOnly.contains(.leftStick(x: 0, y: 0)))
  }
}
