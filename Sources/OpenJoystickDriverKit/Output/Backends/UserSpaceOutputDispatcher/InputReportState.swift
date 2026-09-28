import Foundation

/// Owns the current virtual state and the exact report exposed through both push and get-report
/// APIs.
final class UserSpaceInputReportState: @unchecked Sendable {
  private let format: any VirtualGamepadReportFormat
  private let lock = NSLock()
  private var state = VirtualGamepadState()
  private var report: [UInt8]
  private var remapped = false
  /// The input report input delivery last published; nil once another path published.
  private var deliveredReport: [UInt8]?
  /// Set once the published device closes; host report requests then fail.
  private var closed = false

  var isRemapped: Bool { lock.withLock { remapped } }

  init(format: any VirtualGamepadReportFormat) {
    self.format = format
    self.report = format.buildInputReport(from: VirtualGamepadState())
  }

  func update(remapped: Bool = false, _ body: (inout VirtualGamepadState) -> Void) -> [UInt8] {
    lock.withLock {
      self.remapped = remapped
      body(&state)
      report = format.buildInputReport(from: state)
      return report
    }
  }

  func currentReport() -> [UInt8] { lock.withLock { report } }

  /// Records `report` for delivery and returns whether consumers do not hold it yet.
  func claimDelivery(of report: [UInt8]) -> Bool {
    lock.withLock {
      guard report != deliveredReport else { return false }
      deliveredReport = report
      return true
    }
  }

  func reset() -> [UInt8] {
    lock.withLock {
      state = VirtualGamepadState()
      remapped = false
      deliveredReport = nil
      report = format.buildInputReport(from: state)
      return report
    }
  }

  func close() { lock.withLock { closed = true } }

  var isClosed: Bool { lock.withLock { closed } }

  /// The command a host output report requests of this device's format.
  func consumerOutput(
    _ request: VirtualHostReportRequest
  ) throws(VirtualHostReportError) -> ControllerOutputCommand {
    guard request.type == .output else { throw .unsupported }
    return try ConsumerOutputCodec.decode(request, in: format)
  }

  /// The current input report a host requests, bounded to `maxSize` and including its ID when the
  /// format declares one; the format answers no other report.
  func hostReport(type: VirtualHostReportType, reportID: UInt32, maxSize: Int) throws -> [UInt8] {
    try lock.withLock {
      guard !closed else { throw VirtualHostReportError.closed }
      guard maxSize > 0, let identifier = UInt8(exactly: reportID) else {
        throw VirtualHostReportError.malformed
      }
      guard type == .input, identifier == format.inputReportID ?? 0 else {
        throw VirtualHostReportError.unsupported
      }
      return Array(report.prefix(maxSize))
    }
  }
}
