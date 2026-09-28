import Foundation
import Testing

@testable import OpenJoystickDriverUSB

extension PassiveUSBDescriptorProbeTests {
  @Test
  func superSpeedCompanionsAreOwnedAndValidated() throws {
    let regular: [UInt8] = [
      9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 3, 64, 0, 1, 6,
      0x30, 0, 0, 64, 0,
    ]
    let parsed = try PassiveUSBConfigurationDescriptorParser.parse(
      regular,
      negotiatedSpeed: .superSpeed
    )
    #expect(parsed.interfaces[0].endpoints[0].superSpeedCompanion?.maxBurst == 0)
    #expect(parsed.interfaces[0].endpoints[0].superSpeedPlusCompanion == nil)
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        [9, 2, 15, 0, 0, 1, 0, 0x80, 0x32, 6, 0x30, 0, 0, 0, 0],
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      var duplicate = regular
      duplicate[2] = 37
      duplicate[28] = 0x20
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        duplicate + [6, 0x30, 0, 0, 0, 0],
        negotiatedSpeed: .superSpeed
      )
    }
    let ssp: [UInt8] = [
      9, 2, 39, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 2, 1, 6,
      0x30, 0, 0x80, 1, 0, 8, 0x31, 0, 0, 0x50, 0xC3, 0, 0,
    ]
    let sspParsed = try PassiveUSBConfigurationDescriptorParser.parse(
      ssp,
      negotiatedSpeed: .superSpeedPlus,
      superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
        maxIsoBytesPerBiGen1: 60_000,
        numberOfLanes: 1,
        laneSpeedMantissa: 1,
        laneSpeedMantissaGen1: 1
      )
    )
    #expect(
      sspParsed.interfaces[0].endpoints[0].superSpeedPlusCompanion?.bytesPerInterval == 50_000
    )
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        ssp,
        negotiatedSpeed: .superSpeed,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 1,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 1
        )
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      let orphan: [UInt8] = [
        9, 2, 33, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 0, 1,
        8, 0x31, 0, 0, 0, 0, 0, 0,
      ]
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        orphan,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 1,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 1
        )
      )
    }
  }

  @Test
  func superSpeedPacketBurstMatrixIsTransferSpecific() throws {
    func blob(transfer: UInt8, packet: UInt16, burst: UInt8) -> [UInt8] {
      [
        9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
        UInt8(packet & 0xFF), UInt8(packet >> 8), 1, 6, 0x30, burst, 0, 0, 0,
      ]
    }
    for packet in [UInt16(1), UInt16(1_024)] {

      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 3, packet: packet, burst: 0),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 3, packet: 64, burst: 1),

        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 3, packet: 1_024, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 0, burst: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 512, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
  }

  @Test
  func superSpeedControlAndBulkPacketAndStreamBoundariesAreStrict() throws {
    func blob(
      transfer: UInt8,
      packet: UInt16,
      burst: UInt8,

      attributes: UInt8,
      bytes: UInt16 = 0
    ) -> [UInt8] {
      [
        9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
        UInt8(packet & 0xFF), UInt8(packet >> 8), 1, 6, 0x30, burst, attributes,
        UInt8(bytes & 0xFF), UInt8(bytes >> 8),
      ]
    }
    #expect(throws: Never.self) {

      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 0, packet: 512, burst: 0, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 0, packet: 512, burst: 1, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 0, packet: 64, burst: 0, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 2, packet: 1_024, burst: 0, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    for streams in [UInt8(0), UInt8(16)] {
      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 2, packet: 1_024, burst: 0, attributes: streams),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    for attributes in [UInt8(17), UInt8(0x20), UInt8(0x80)] {
      #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 2, packet: 1_024, burst: 0, attributes: attributes),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 2, packet: 1_024, burst: 0, attributes: 0, bytes: 1),
        negotiatedSpeed: .superSpeed
      )
    }
  }

  @Test
  func superSpeedInterruptAndIsoPacketAndByteBoundariesAreStrict() throws {
    func blob(
      transfer: UInt8,
      packet: UInt16,
      burst: UInt8,
      attributes: UInt8 = 0,
      bytes: UInt16 = 0
    ) -> [UInt8] {
      [
        9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
        UInt8(packet & 0xFF), UInt8(packet >> 8), 1, 6, 0x30, burst, attributes,
        UInt8(bytes & 0xFF), UInt8(bytes >> 8),
      ]
    }
    for packet in [UInt16(0), UInt16(1_025)] {
      #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 3, packet: packet, burst: 0),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_025, burst: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 0, attributes: 0x04),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 1, attributes: 0, bytes: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 0, attributes: 0, bytes: 1_024),
        negotiatedSpeed: .superSpeed
      )
    }
  }

  @Test
  func sspBoundaryContextAndOrderingCasesAreTyped() throws {
    func fixture(dw: UInt32 = 50_000, marker: UInt8 = 0x80, sspBytes: UInt16 = 1) -> [UInt8] {
      [
        9, 2, 39, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 2, 1,
        6, 0x30, 0, marker, UInt8(sspBytes & 0xFF), UInt8(sspBytes >> 8), 8, 0x31, 0, 0,
        UInt8(dw & 0xFF), UInt8((dw >> 8) & 0xFF), UInt8((dw >> 16) & 0xFF), UInt8(dw >> 24),
      ]
    }
    let context = PassiveUSBSuperSpeedPlusValidationContext(
      maxIsoBytesPerBiGen1: 60_000,
      numberOfLanes: 1,
      laneSpeedMantissa: 1,
      laneSpeedMantissaGen1: 1
    )
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(dw: 49_152),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(dw: 60_000),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(dw: 59_999),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(),
        negotiatedSpeed: .superSpeed,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(),
        negotiatedSpeed: .superSpeedPlus
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(marker: 0),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(sspBytes: 2),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    var intervening = fixture()
    intervening.insert(contentsOf: [3, 0x24, 0], at: 31)
    intervening[2] = UInt8(intervening.count)
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        intervening,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    var reserved = fixture()
    reserved[30] = 1
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        reserved,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
  }
}
