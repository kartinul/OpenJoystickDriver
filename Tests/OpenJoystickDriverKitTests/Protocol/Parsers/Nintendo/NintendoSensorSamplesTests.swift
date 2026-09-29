import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NintendoSensorSamplesTests {
  private func report() -> Data {
    var bytes = [UInt8](repeating: 0, count: 49)
    bytes[0] = 0x30
    bytes[1] = 255
    bytes[7] = 8
    bytes[8] = 128
    bytes[10] = 8
    bytes[11] = 128
    for index in 0..<3 {
      let offset = 13 + 12 * index
      bytes[offset] = UInt8(index + 1)
      bytes[offset + 7] = 0x80
      bytes[offset + 8] = 0xFF
      bytes[offset + 9] = 0x7F
      bytes[offset + 10] = 0xFF
      bytes[offset + 11] = 0xFF
    }
    return Data(bytes)
  }

  private func samples(_ event: ControllerEvent?) -> [ControllerMotionSample] {
    event?.motion ?? []
  }

  @Test
  func threeRawSamplesRetainOrderAndUseExplicitHostEstimates() throws {
    let parser: any PhysicalProtocolDriver = Switch1Driver()
    let first = samples(try parser.parseReport(report(), at: 100_000_000))
    // Pro nominal: raw (x, y, z) lands canonical as (-y, x, z).
    let gravity = ControllerMotionUnits.standardGravity
    #expect(first.map(\.acceleration.y) == [1, 2, 3].map { $0 / 4096 * gravity })
    let gyro = radiansPerSecond(-32_767 / 14.2842, -32_768 / 14.2842, -1 / 14.2842)
    #expect(first.allSatisfy { isClose($0.angularVelocity, gyro) })
    #expect(first.map(\.timestamp.monotonic.nanoseconds) == [100, 105, 110].map { $0 * 1_000_000 })
    #expect(first.map(\.timestamp.sequenceIndex) == [0, 1, 2])
    #expect(
      first.allSatisfy {
        $0.timestamp.basis == .hostEstimate && $0.timestamp.rawCounter == 255
          && $0.timestamp.tickNanosecondsNumerator == nil
          && $0.timestamp.tickNanosecondsDenominator == nil
      }
    )
    let second = samples(try parser.parseReport(report(), at: 115_000_000))
    #expect(
      second.map(\.timestamp.monotonic.nanoseconds) == [115, 120, 125].map { $0 * 1_000_000 }
    )
    #expect(second.map(\.timestamp.sequenceIndex) == [3, 4, 5])
  }

  @Test
  func backwardReceiptDoesNotReverseTimeAndLongGapDoesNotStretchSamples() throws {
    let parser = Switch1Driver()
    _ = try parser.parseReport(report(), at: 100_000_000)
    let backward = samples(try parser.parseReport(report(), at: 90_000_000))
    #expect(
      backward.map(\.timestamp.monotonic.nanoseconds) == [110, 110, 110].map { $0 * 1_000_000 }
    )
    let gap = samples(try parser.parseReport(report(), at: 1_100_000_000))
    #expect(
      gap.map(\.timestamp.monotonic.nanoseconds) == [1_100, 1_105, 1_110].map { $0 * 1_000_000 }
    )
  }

  @Test
  func shortReportCannotAdvanceSensorClock() throws {
    let parser = Switch1Driver()
    let short = try parser.parseReport(report().prefix(12), at: 1)
    #expect(samples(short).isEmpty)
    let full = samples(try parser.parseReport(report(), at: 100_000_000))
    #expect(full.first?.timestamp.monotonic.nanoseconds == 100_000_000)
    #expect(full.first?.timestamp.sequenceIndex == 0)
    #expect(parser.capabilities.motion)
    #expect(parser.capabilities.touchContactCount == 0)
  }
}
