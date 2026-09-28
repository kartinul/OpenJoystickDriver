import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHostReportTests {
  @Test
  func numberedReportsCarryTheirIDAsByteZero() throws {
    let numbered = try VirtualHostReportRequest(type: .output, reportID: 5, bytes: [5, 5, 9])
    #expect(numbered.payload == [5, 9])
    // An unnumbered report is all data, whatever its first byte.
    let unnumbered = try VirtualHostReportRequest(type: .output, reportID: 0, bytes: [5, 9])
    #expect(unnumbered.payload == [5, 9])
    #expect(throws: VirtualHostReportError.malformed) {
      try VirtualHostReportRequest(type: .output, reportID: 5, bytes: [9])
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try VirtualHostReportRequest(type: .output, reportID: 256, bytes: [])
    }
  }

  @Test
  func hostReportChecksTypeIdentityCapacityAndLifetime() throws {
    let input = UserSpaceInputReportState(format: OJDGenericGamepadFormat())
    let current = input.update { $0.buttons = 1 }
    #expect(try input.hostReport(type: .input, reportID: 0, maxSize: 3) == Array(current.prefix(3)))
    for type in [VirtualHostReportType.feature, .output] {
      #expect(throws: VirtualHostReportError.unsupported) {
        try input.hostReport(type: type, reportID: 0, maxSize: 64)
      }
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try input.hostReport(type: .input, reportID: 1, maxSize: 64)
    }
    for size in [-1, 0] {
      #expect(throws: VirtualHostReportError.malformed) {
        try input.hostReport(type: .input, reportID: 0, maxSize: size)
      }
    }
    input.close()
    #expect(input.isClosed)
    #expect(throws: VirtualHostReportError.closed) {
      try input.hostReport(type: .input, reportID: 0, maxSize: 64)
    }
  }

  @Test
  func genericRumbleAcceptsShortXbox360UnnumberedFraming() throws {
    let input = UserSpaceInputReportState(format: OJDGenericGamepadFormat())
    let request = try VirtualHostReportRequest(
      type: .output,
      reportID: 0,
      bytes: [8, 0, 127, 255, 0, 0, 0]
    )
    #expect(try input.consumerOutput(request) == .consumerRumble(left: 127, right: 255))
    let malformed = try VirtualHostReportRequest(type: .output, reportID: 0, bytes: [8, 0, 127])
    #expect(throws: VirtualHostReportError.malformed) { try input.consumerOutput(malformed) }
    let feature = try VirtualHostReportRequest(
      type: .feature,
      reportID: 0,
      bytes: [8, 0, 127, 255]
    )
    #expect(throws: VirtualHostReportError.unsupported) { try input.consumerOutput(feature) }
  }

  @Test
  func setReportAfterInputCloseIsClosed() async throws {
    let input = UserSpaceInputReportState(format: OJDGenericGamepadFormat())
    let sender = UserSpaceReportSender()
    let isOpen: @Sendable () -> Bool = { true }
    let handler = UserSpaceHostReportHandler(
      identifier: DeviceIdentifier(vendorID: 1, productID: 2),
      input: input,
      sender: sender,
      isOpen: isOpen,
      onOutput: nil
    ) { _ in }
    input.close()
    #expect(throws: VirtualHostReportError.closed) {
      try handler.setReport(type: .output, reportID: 0, bytes: [0x4F, 10, 20, 0, 0])
    }
    await sender.beginClose().value
  }

  @Test
  func nativeErrorsPreserveFailureClassification() {
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.unsupported)
        == kIOReturnUnsupported
    )
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.malformed)
        == kIOReturnBadArgument
    )
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.tooLarge)
        == kIOReturnMessageTooLarge
    )
    #expect(
      UserSpaceHostReportHandler.ioKitError(VirtualHostReportError.closed) == kIOReturnNotOpen
    )
  }
}
