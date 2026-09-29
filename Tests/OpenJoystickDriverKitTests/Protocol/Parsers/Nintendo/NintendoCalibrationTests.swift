import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NintendoCalibrationTests {
  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func factoryReplyCalibratesAllThreeSamples(_ layout: NintendoControllerLayout) throws {
    let parser = Switch1Driver(layout: layout, isBluetooth: true)
    let requests = parser.startupWrites().hidOutputs
    #expect(Array(requests[3].bytes.suffix(6)) == [0x10, 0x20, 0x60, 0, 0, 24])
    #expect(Array(requests[4].bytes.suffix(6)) == [0x10, 0x26, 0x80, 0, 0, 20])
    #expect(try parser.parseReport(reply(), at: 1) == nil)
    let samples = try samples(parser)
    #expect(samples.count == 3)
    #expect(samples.map(\.timestamp.sequenceIndex) == [0, 1, 2])
    let right = layout == .rightJoyCon
    for sample in samples {
      #expect(sample.calibrationSource == .deviceFactory)
      #expect(sample.calibrationRevision == 1)
      #expect(
        isClose(sample.angularVelocity, radiansPerSecond(right ? 20 : -20, 10, right ? -30 : 30))
      )
      #expect(
        isClose(sample.acceleration, metresPerSecondSquared(right ? 2 : -2, 1, right ? -3 : 3))
      )
    }
  }

  @Test
  func unrelatedMalformedAndUnsolicitedRepliesCannotInstallCalibration() throws {
    let parser = Switch1Driver()
    _ = try parser.parseReport(reply())
    #expect(try samples(parser).first?.calibrationSource == .nominalDeviceScale)
    _ = parser.startupWrites()
    for offset in [13, 14, 15, 16, 17, 18, 19] {
      var invalid = reply()
      invalid[offset] = 0x7F
      _ = try parser.parseReport(invalid)
      #expect(try samples(parser).first?.calibrationSource == .nominalDeviceScale)
    }
    _ = try parser.parseReport(reply().prefix(43))
    #expect(try samples(parser).first?.calibrationSource == .nominalDeviceScale)
    var erased = reply()
    erased.replaceSubrange(20..<44, with: Array(repeating: UInt8(255), count: 24))
    _ = try parser.parseReport(erased)
    #expect(try samples(parser).first?.calibrationSource == .nominalDeviceScale)
    _ = try parser.parseReport(reply())
    #expect(try samples(parser).first?.calibrationSource == .deviceFactory)
  }

  private func reply() -> Data {
    var data = Data(repeating: 0, count: 49)
    data[0] = 0x21
    data[13] = 0x90
    data[14] = 0x10
    data[15] = 0x20
    data[16] = 0x60
    data[19] = 24
    for axis in 0..<3 {
      write(100, into: &data, at: 20 + axis * 2)
      write(16484, into: &data, at: 26 + axis * 2)
      let gyroOffset = Int16((axis + 1) * 10)
      write(gyroOffset, into: &data, at: 32 + axis * 2)
      write(gyroOffset + 9360, into: &data, at: 38 + axis * 2)
    }
    return data
  }

  @Test(arguments: [false, true])
  func userOffsetsCombineWithFactorySensitivityInEitherOrder(userFirst: Bool) throws {
    let parser = Switch1Driver(isBluetooth: true)
    _ = parser.startupWrites()
    let first = userFirst ? userReply() : reply()
    let second = userFirst ? reply() : userReply()
    _ = try parser.parseReport(first)
    #expect(
      try samples(parser).first?.calibrationSource
        == (userFirst ? .nominalDeviceScale : .deviceFactory)
    )
    _ = try parser.parseReport(second)
    let sample = try #require(samples(parser).first)
    let reading = Calibrated(sample)
    #expect(reading.source == .factoryWithUserOffsets)
    #expect(reading.revision == (userFirst ? 1 : 2))
    // User offsets equal the fixture's raw gyro readings, so the calibrated rotation is zero.
    #expect(isClose(reading.angularVelocity, ControllerMotionVector(x: 0, y: 0, z: 0)))
    #expect(isClose(reading.acceleration, metresPerSecondSquared(-4, 2, 6)))
    #expect(
      try JSONDecoder().decode(ControllerMotionSample.self, from: JSONEncoder().encode(sample))
        == sample
    )
    // Duplicate replies cannot replace a completed acquisition's snapshot.
    _ = try parser.parseReport(userReply(invalid: true))
    #expect(try samples(parser).first.map(Calibrated.init) == reading)
  }

  @Test
  func invalidUserRangesRetainFactoryAndNewParserStartsNominal() throws {
    let parser = Switch1Driver(isBluetooth: true)
    _ = parser.startupWrites()
    _ = try parser.parseReport(reply())
    let factory = try #require(samples(parser).first.map(Calibrated.init))
    _ = try parser.parseReport(userReply(invalid: true))
    #expect(try samples(parser).first.map(Calibrated.init) == factory)
    #expect(try samples(Switch1Driver()).first?.calibrationSource == .nominalDeviceScale)
  }

  @Test
  func reacquisitionOnlyAdvancesForChangedCoefficients() throws {
    let parser = Switch1Driver(isBluetooth: true)
    _ = parser.startupWrites()
    _ = try parser.parseReport(reply())
    #expect(try samples(parser).first?.calibrationRevision == 1)
    _ = parser.startupWrites()
    _ = try parser.parseReport(reply())
    #expect(try samples(parser).first?.calibrationRevision == 1)
    _ = parser.startupWrites()
    var changed = reply()
    write(11, into: &changed, at: 32)
    _ = try parser.parseReport(changed)
    #expect(try samples(parser).first?.calibrationRevision == 2)
  }

  @Test
  func recoveryOnlyRetriesPendingReadsAndExpiryRetainsAcceptedCalibration() throws {
    let parser = Switch1Driver(isBluetooth: true)
    _ = parser.startupWrites()
    let retry = parser.startupRecoveryWrites().hidOutputs
    #expect(retry.count == 2)
    #expect(retry.map { $0.bytes[1] } == [5, 6])
    _ = try parser.parseReport(reply())
    let factory = try #require(samples(parser).first.map(Calibrated.init))
    let remaining = parser.startupRecoveryWrites().hidOutputs
    #expect(remaining.count == 1)
    #expect(Array(try #require(remaining.first).bytes.suffix(5)) == [0x26, 0x80, 0, 0, 20])
    parser.expireStartupRecovery()
    #expect(parser.startupRecoveryWrites().hidOutputs.isEmpty)
    _ = try parser.parseReport(userReply())
    #expect(try samples(parser).first.map(Calibrated.init) == factory)
    // A later explicit acquisition begins fresh and can combine both new replies.
    _ = parser.startupWrites()
    _ = try parser.parseReport(userReply())
    #expect(try samples(parser).first.map(Calibrated.init) == factory)
    _ = try parser.parseReport(reply())
    #expect(try samples(parser).first?.calibrationSource == .factoryWithUserOffsets)
  }

  @Test
  func pipelineStopExpiresOutstandingSPIReads() async {
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x057E, productID: 0x2009),
      transport: .hid(locationID: 84),
      driver: Switch1Driver(isBluetooth: true),
      dispatcher: LoggingOutputDispatcher()
    )
    await pipeline.start()
    _ = await pipeline.hidStartupWrites()
    #expect(await pipeline.hidStartupRecoveryWrites().count == 2)
    await pipeline.stop()
    await pipeline.start()
    #expect(await pipeline.hidStartupRecoveryWrites().isEmpty)
    await pipeline.stop()
  }

  private func userReply(invalid: Bool = false) -> Data {
    var data = Data(repeating: 0, count: 49)
    data[0] = 0x21
    data[13] = 0x90
    data[14] = 0x10
    data[15] = 0x26
    data[16] = 0x80
    data[19] = 20
    data[20] = 0xB2
    data[21] = 0xA1
    for axis in 0..<3 {
      write(invalid ? 16484 : 8292, into: &data, at: 22 + axis * 2)
      write(Int16((axis + 1) * 110), into: &data, at: 34 + axis * 2)
    }
    return data
  }

  private func samples(_ parser: Switch1Driver) throws -> [ControllerMotionSample] {
    var data = Data(repeating: 0, count: 49)
    data[0] = 0x30
    for index in 0..<3 {
      for axis in 0..<3 {
        write(Int16((axis + 1) * 4096), into: &data, at: 13 + index * 12 + axis * 2)
        write(Int16((axis + 1) * 110), into: &data, at: 19 + index * 12 + axis * 2)
      }
    }
    return try parser.parseReport(data, at: 100)?.motion ?? []
  }

  private func write(_ value: Int16, into data: inout Data, at offset: Int) {
    let raw = UInt16(bitPattern: value)
    data[offset] = UInt8(truncatingIfNeeded: raw)
    data[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}

/// The calibrated values of a sample without its per-report timestamp.
private struct Calibrated: Equatable {
  let angularVelocity: ControllerMotionVector
  let acceleration: ControllerMotionVector
  let source: ControllerMotionCalibrationSource
  let revision: UInt64

  init(_ sample: ControllerMotionSample) {
    angularVelocity = sample.angularVelocity
    acceleration = sample.acceleration
    source = sample.calibrationSource
    revision = sample.calibrationRevision
  }
}
