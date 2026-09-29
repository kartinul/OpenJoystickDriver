import Foundation
import IOKit.hid

/// Request contract for `IOHIDUserDevice`'s synchronous report callbacks.
final class UserSpaceHostReportHandler: Sendable {
  /// Serializes consuming a request with enqueueing it, so publication follows callback order.
  private let lock = NSLock()
  private let identifier: DeviceIdentifier
  private let input: UserSpaceInputReportState
  private let sender: UserSpaceReportSender
  private let isOpen: @Sendable () -> Bool
  private let onOutput: UserSpaceOutputDispatcher.OutputCommandHandler?
  private let onRumbleStatus: @Sendable (String) -> Void

  init(
    identifier: DeviceIdentifier,
    input: UserSpaceInputReportState,
    sender: UserSpaceReportSender,
    isOpen: @escaping @Sendable () -> Bool,
    onOutput: UserSpaceOutputDispatcher.OutputCommandHandler?,
    onRumbleStatus: @escaping @Sendable (String) -> Void
  ) {
    self.identifier = identifier
    self.input = input
    self.sender = sender
    self.isOpen = isOpen
    self.onOutput = onOutput
    self.onRumbleStatus = onRumbleStatus
  }

  /// Native callbacks follow the IOKit/HIDAPI convention: numbered buffers include byte-zero ID.
  /// The callback acknowledges validated enqueueing, not publication.
  func setReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) throws -> UserSpaceReportSender.SubmissionReceipt {
    try lock.withLock {
      guard isOpen(), !input.isClosed else { throw VirtualHostReportError.closed }
      let request = try VirtualHostReportRequest(type: type, reportID: reportID, bytes: bytes)
      let command = try input.consumerOutput(request)
      return sender.submit { [self] in
        guard isOpen() else { throw VirtualHostReportError.closed }
        if let rumble = Self.rumbleIntensities(command) {
          let status =
            "app report id=\(reportID) L=\(rumble.leftMain.byte) R=\(rumble.rightMain.byte) "
            + "LT=\(rumble.leftTrigger.byte) RT=\(rumble.rightTrigger.byte)"
          onRumbleStatus(status)
          print("[UserSpaceOutputDispatcher] App rumble report: \(identifier) \(status)")
        }
        onOutput?(identifier, command)
        return []
      }
    }
  }

  func getReport(type: VirtualHostReportType, reportID: UInt32, maxSize: Int) throws -> [UInt8] {
    guard isOpen() else { throw VirtualHostReportError.closed }
    return try input.hostReport(type: type, reportID: reportID, maxSize: maxSize)
  }

  /// The requested rumble intensities of a rumble command; stop-rumble requests them all off.
  private static func rumbleIntensities(_ command: ControllerOutputCommand) -> RumbleIntensities? {
    switch command {
    case .setRumble(let intensities, _): intensities
    case .stopRumble: .off
    default: nil
    }
  }

  static func reportType(_ type: IOHIDReportType) throws -> VirtualHostReportType {
    switch type {
    case kIOHIDReportTypeInput: .input
    case kIOHIDReportTypeOutput: .output
    case kIOHIDReportTypeFeature: .feature
    default: throw VirtualHostReportError.unsupported
    }
  }

  static func ioKitError(_ error: any Error) -> IOReturn {
    switch error {
    case VirtualHostReportError.unsupported: kIOReturnUnsupported
    case VirtualHostReportError.malformed: kIOReturnBadArgument
    case VirtualHostReportError.tooLarge: kIOReturnMessageTooLarge
    case VirtualHostReportError.closed: kIOReturnNotOpen
    case is CancellationError: kIOReturnAborted
    default: kIOReturnError
    }
  }
}
