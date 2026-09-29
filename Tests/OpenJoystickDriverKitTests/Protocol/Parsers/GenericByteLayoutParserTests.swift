import Foundation
import OpenJoystickDriverKit
import Testing

struct GenericByteLayoutParserTests {
  // MARK: - Helpers

  private func neutralReport() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 22)
    // Sticks rest at 127/128, the pair that centers on 127.5.
    bytes[3] = 127  // LS_X
    bytes[4] = 128  // LS_Y
    bytes[5] = 127  // RS_X
    bytes[6] = 128  // RS_Y
    return bytes
  }

  private func report(
    meta: UInt8 = 0,
    lsX: UInt8 = 127,
    lsY: UInt8 = 128,
    rsX: UInt8 = 127,
    rsY: UInt8 = 128,
    dpad: UInt8 = 0,
    face: UInt8 = 0,
    lb: Bool = false,
    rb: Bool = false,
    lt: UInt8 = 0,
    rt: UInt8 = 0
  ) -> [UInt8] {
    var bytes = neutralReport()
    bytes[1] = meta
    bytes[3] = lsX
    bytes[4] = lsY
    bytes[5] = rsX
    bytes[6] = rsY
    // dpad bits: 1 = right, 2 = left, 4 = up, 8 = down
    if dpad & 0x01 != 0 { bytes[7] = 0x80 }
    if dpad & 0x02 != 0 { bytes[8] = 0x80 }
    if dpad & 0x04 != 0 { bytes[9] = 0x80 }
    if dpad & 0x08 != 0 { bytes[10] = 0x80 }
    if face & 0x80 != 0 { bytes[11] = 0x80 }  // Y
    if face & 0x40 != 0 { bytes[12] = 0x80 }  // B
    if face & 0x20 != 0 { bytes[13] = 0x80 }  // A
    if face & 0x10 != 0 { bytes[14] = 0x80 }  // X
    if lb { bytes[15] = 0x80 }
    if rb { bytes[16] = 0x80 }
    bytes[17] = lt
    bytes[18] = rt
    return bytes
  }

  // MARK: - Button press/release

  @Test
  func faceButtonsEmitPressAndRelease() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    let pressed = try parser.parse(data: Data(report(face: 0x20 | 0x10)))  // A + X
    #expect(pressed.contains(.buttonPressed(.a)))
    #expect(pressed.contains(.buttonPressed(.x)))

    let released = try parser.parse(data: Data(report(face: 0x20)))  // A only
    #expect(released.contains(.buttonReleased(.x)))
    #expect(!released.contains(.buttonReleased(.a)))

    let releasedAll = try parser.parse(data: Data(report(face: 0)))
    #expect(releasedAll.contains(.buttonReleased(.a)))
  }

  @Test
  func metaButtonsEmitPressAndRelease() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    let pressed = try parser.parse(data: Data(report(meta: 0x01 | 0x02 | 0x04 | 0x08)))
    #expect(pressed.contains(.buttonPressed(.back)))
    #expect(pressed.contains(.buttonPressed(.start)))
    #expect(pressed.contains(.buttonPressed(.leftStick)))
    #expect(pressed.contains(.buttonPressed(.rightStick)))

    let released = try parser.parse(data: Data(report(meta: 0x01 | 0x04)))
    #expect(released.contains(.buttonReleased(.start)))
    #expect(released.contains(.buttonReleased(.rightStick)))
    #expect(!released.contains(.buttonReleased(.back)))
  }

  @Test
  func bumpersEmitPressAndRelease() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    let pressed = try parser.parse(data: Data(report(lb: true, rb: true)))
    #expect(pressed.contains(.buttonPressed(.leftBumper)))
    #expect(pressed.contains(.buttonPressed(.rightBumper)))

    let released = try parser.parse(data: Data(report(lb: true)))
    #expect(released.contains(.buttonReleased(.rightBumper)))
  }

  // MARK: - Dpad

  @Test
  func dpadEmitsCardinalAndDiagonal() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    let up = try parser.parse(data: Data(report(dpad: 0x04)))
    #expect(up.contains(.dpadChanged(.north)))

    let upRight = try parser.parse(data: Data(report(dpad: 0x04 | 0x01)))
    #expect(upRight.contains(.dpadChanged(.northEast)))

    let downLeft = try parser.parse(data: Data(report(dpad: 0x08 | 0x02)))
    #expect(downLeft.contains(.dpadChanged(.southWest)))

    let neutral = try parser.parse(data: Data(report(dpad: 0)))
    #expect(neutral.contains(.dpadChanged(.neutral)))
  }

  // MARK: - Sticks

  @Test
  func sticksReportRawDeviceOrientation() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    // Center 127.5, span 127.5: byte 255 -> +1, byte 0 -> -1 (exact).
    // Sign is reported raw; inversion is a profile-level preference.
    let moved = try parser.parse(data: Data(report(lsX: 255, lsY: 0, rsX: 0, rsY: 255)))
    #expect(moved.contains(.leftStickChanged(x: 1, y: -1)))
    #expect(moved.contains(.rightStickChanged(x: -1, y: 1)))

    let back = try parser.parse(data: Data(report(lsX: 0, lsY: 255, rsX: 255, rsY: 0)))
    #expect(back.contains(.leftStickChanged(x: -1, y: 1)))
    #expect(back.contains(.rightStickChanged(x: 1, y: -1)))
  }

  @Test
  func sticksApplyDeadzone() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    // 128 is within deadzone of center 127.5
    let small = try parser.parse(data: Data(report(lsX: 128, lsY: 128)))
    #expect(!small.contains { if case .leftStickChanged = $0 { true } else { false } })

    // 140 is 12.5 from center 127.5, normalized 0.098, just outside the 0.08 deadzone
    let large = try parser.parse(data: Data(report(lsX: 140, lsY: 140)))
    #expect(large.contains { if case .leftStickChanged = $0 { true } else { false } })
  }

  // MARK: - Triggers

  @Test
  func triggersNormalize() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))

    let pressed = try parser.parse(data: Data(report(lt: 255, rt: 128)))
    #expect(pressed.contains(.leftTriggerChanged(1)))
    let right = pressed.compactMap { event -> Float? in
      if case .rightTriggerChanged(let value) = event { return value }
      return nil
    }.first
    #expect(right.map { abs($0 - 128.0 / 255.0) < 0.0001 } == true)
  }

  // MARK: - Malformed frames

  @Test
  func shortFramePreservesState() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))
    _ = try parser.parse(data: Data(report(face: 0x20)))  // press A

    let short = try parser.parse(data: Data([0x01, 0x02, 0x03]))
    #expect(short.isEmpty)

    // State preserved: releasing A still emits the event
    let released = try parser.parse(data: Data(report(face: 0)))
    #expect(released.contains(.buttonReleased(.a)))
  }

  @Test
  func repeatedNeutralReportEmitsNothing() throws {
    let parser = GenericByteLayoutParser()
    _ = try parser.parse(data: Data(neutralReport()))
    let second = try parser.parse(data: Data(neutralReport()))
    #expect(second.isEmpty)
  }

  /// The backend discards raw reports for parsers that decode descriptor
  /// elements, so this parser must never adopt that protocol.
  @Test
  func parserIsNotRoutedThroughDescriptorElements() {
    #expect(!(GenericByteLayoutParser() is any HIDElementValueParser))
  }
}
