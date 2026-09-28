/// The writes OJD still makes to a controller macOS serves natively: only what macOS leaves
/// undone for that family. Every other native controller gets none.
struct NativeGamepadWrites: Equatable, Sendable {
  /// Lighting OJD drives because macOS does not.
  let lightingFeatures: Set<PhysicalLightingFeature>
  /// HID output report IDs that carry that lighting; the write executors refuse every other
  /// output report and every feature report.
  let outputReportIDs: Set<UInt8>
  /// Player indicator OJD sets once the controller binds.
  let startupPlayerIndicator: PhysicalPlayerIndicator?

  static let none = Self(lightingFeatures: [], outputReportIDs: [], startupPlayerIndicator: nil)

  /// The allowance table, keyed by bound protocol.
  static func allowance(for protocolID: PhysicalProtocolID) -> Self {
    switch protocolID {
    // macOS never lights a DualShock 3 / Sixaxis player LED. Output report 0x01 sets it; its
    // rumble fields stay off because rumble is not allowed.
    case .sonySixaxis:
      Self(
        lightingFeatures: [.playerIndicator],
        outputReportIDs: [0x01],
        startupPlayerIndicator: .player1
      )
    default: .none
    }
  }

  /// The write-executor gate for a native controller.
  func permits(_ report: PhysicalHIDOutputReport, kind: PhysicalHIDReportKind) -> Bool {
    kind == .output && outputReportIDs.contains(report.reportID)
  }

  /// The driver's output capabilities narrowed to this allowance.
  func narrowing(
    _ capabilities: PhysicalControllerOutputCapabilities
  ) -> PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      lightingFeatures: capabilities.lightingFeatures.filter { lightingFeatures.contains($0) }
    )
  }
}
