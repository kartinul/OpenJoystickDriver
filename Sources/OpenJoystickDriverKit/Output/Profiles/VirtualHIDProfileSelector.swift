/// Chooses the one virtual HID profile a logical controller publishes: the Advanced override when
/// the controller fits it, else `hid-xbox-one-s-bt` when its primary controls fit, else
/// `hid-generic`.
///
/// Selection reads only the controller's declared controls and the user's Advanced override.
/// Protocol, manufacturer, consumer, macOS version, and access backend never participate, and a
/// natively passed-through controller never reaches selection.
public enum VirtualHIDProfileSelector {
  /// The outcome of selection.
  public struct Selection: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
      case automatic
      case override
      /// The controller could not satisfy this override, so automatic selection ran instead.
      case automaticAfterRejecting(VirtualHIDProfileID)
    }

    public let profileID: VirtualHIDProfileID
    public let source: Source
  }

  /// Controls whose representation decides the profile: the Xbox layout plus the digital trigger
  /// buttons. System controls other than `view` and `menu`, and every extended control, stay in
  /// OJD's normalized API and never force `hid-generic`.
  public static let primaryControls: Set<ControlID> = ControlID.xboxLayout.union([
    .leftTriggerButton, .rightTriggerButton,
  ])

  /// Selects the profile for a controller that declares `controls`.
  ///
  /// - Throws: `ProtocolBindingReason.virtualProfileUnavailable` when the selected profile cannot
  ///   represent the controller's primary controls.
  public static func select(
    controls: Set<ControlID>,
    override: VirtualHIDProfileID?
  ) throws(ProtocolBindingReason) -> Selection {
    try select(controls: controls, override: override, slots: \.representableControls)
  }

  /// `select(controls:override:)` over explicit profile slots, so tests can reach the branches
  /// today's two profiles never take.
  static func select(
    controls: Set<ControlID>,
    override: VirtualHIDProfileID?,
    slots: (VirtualHIDProfileID) -> Set<ControlID>
  ) throws(ProtocolBindingReason) -> Selection {
    let required = controls.intersection(primaryControls)
    func fits(_ profile: VirtualHIDProfileID) -> Bool { represents(required, in: slots(profile)) }
    if let override, fits(override) { return Selection(profileID: override, source: .override) }
    let automatic: VirtualHIDProfileID = fits(.xboxOneSBluetooth) ? .xboxOneSBluetooth : .generic
    guard fits(automatic) else { throw .virtualProfileUnavailable }
    return Selection(
      profileID: automatic,
      source: override.map(Selection.Source.automaticAfterRejecting) ?? .automatic
    )
  }

  /// Whether `slots` carry every control in `required`. A trigger button fits the analog trigger
  /// slot, published at `0` or `65535` when the trigger is digital-only; a controller declaring
  /// both shares that one slot, because the report encoder merges them.
  static func represents(_ required: Set<ControlID>, in slots: Set<ControlID>) -> Bool {
    required.allSatisfy { control in
      switch control {
      case .leftTriggerButton: return slots.contains(control) || slots.contains(.leftTrigger)
      case .rightTriggerButton: return slots.contains(control) || slots.contains(.rightTrigger)
      default: return slots.contains(control)
      }
    }
  }
}
