import Foundation

/// Revocable authority for power notifications delivered by one runtime start.
///
/// A caller must invalidate the session before stopping its manager. DeviceManager checks this
/// token after the actor hop, so a queued notification from an earlier runtime cannot stop or
/// restart a later manager lifecycle.
public final class DeviceManagerSystemPowerEventSession: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true

  public init() {}

  var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return active
  }

  public func invalidate() {
    lock.lock()
    active = false
    lock.unlock()
  }
}

/// Marks physical output issued by controller teardown. Once teardown starts, output guards accept
/// only writes made inside this scope, so a request already in flight cannot re-enable an output
/// after teardown neutralized it.
enum ControllerTeardownOutput {
  @TaskLocal
  static var isActive = false
}

func controllerDisplayName(productName: String?, vendorID: UInt16, productID: UInt16) -> String {
  if let productName {
    let value = productName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { return value }
  }
  return String(format: "Controller %04x:%04x", vendorID, productID)
}

let usbDetectionPollNanoseconds: UInt64 = 500_000_000
let devicePermissionWatchNanoseconds: UInt64 = 1_000_000_000
let deviceDiscoveryNanosecondsPerMillisecond: UInt64 = 1_000_000
let maxRumbleDurationMs = 5_000
let usbVendorSpecificClass: UInt8 = 0xFF

struct RumbleStopTokenRegistry {
  private var generations: [DeviceIdentifier: UInt64] = [:]

  mutating func replace(for identifier: DeviceIdentifier) -> UInt64 {
    let generation = (generations[identifier] ?? 0) &+ 1
    generations[identifier] = generation
    return generation
  }

  func isCurrent(_ generation: UInt64, for identifier: DeviceIdentifier) -> Bool {
    generations[identifier] == generation
  }

  mutating func remove(_ identifier: DeviceIdentifier) {
    generations.removeValue(forKey: identifier)
  }

  mutating func removeAll() { generations.removeAll() }
}

struct HIDDeviceInitialization {
  let connection: HIDDeviceConnection
  let task: Task<Void, Never>
}

/// Manages device detection and pipeline lifecycle for all
/// connected controllers.
/// Uses dual detection: an Apple USB transport provider for raw interfaces and
/// the OS-generation HID wrapper for HID-class controllers.
public actor DeviceManager {

  let protocolDriverRegistry: ProtocolDriverRegistry
  let dispatcher: any OutputDispatcher
  let permissionManager: PermissionManager
  let hidManager: HIDManager
  let usbTransportProvider: (any USBTransportProvider)?
  let wirelessControllerDisconnector: (any WirelessControllerDisconnecting)?
  var pipelines: [DeviceIdentifier: DevicePipeline] = [:]
  var deviceInfos: [DeviceIdentifier: DeviceInfo] = [:]
  var detectionTasks: [Task<Void, Never>] = []
  var hidDetectionTask: Task<Void, Never>?
  var hidDetectionSessionID: UUID?
  var hidInitializationTasks: [HIDInitializationKey: HIDDeviceInitialization] = [:]
  /// The controller each bound HID protocol role serves, keyed by its connection ID; input from
  /// a role's connection routes only to it.
  var hidRoleConnections: [UUID: DeviceIdentifier] = [:]
  var hidPeriodicOutputTasks: [DeviceIdentifier: Task<Void, Never>] = [:]
  /// One output queue per interface, for HID and raw-USB controllers alike.
  var hidOutputQueues: [DeviceIdentifier: PhysicalHIDOutputSerialQueue] = [:]
  /// The last removed queue per interface; the interface's next queue starts after it drains.
  var retiredHIDOutputQueues: [DeviceIdentifier: PhysicalHIDOutputSerialQueue] = [:]
  var permissionWatchTask: Task<Void, Never>?
  var lifecycleGeneration: UInt64 = 0
  var isStopping = false
  /// Set by `start()` and cleared by `stop()`; a wake restarts only a started manager.
  var isStarted = false
  var isSystemSleeping = false
  /// Controllers the user suspended; a pipeline for one of these identities starts suspended.
  /// Resume, physical disconnect, and `stop()` remove entries; sleep keeps them.
  var suspendedControllerIdentities: Set<DeviceIdentifier> = []
  var externalOutputAllowed = true
  var lastPhysicalHIDOutputNanoseconds: [DeviceIdentifier: UInt64] = [:]
  var rumbleStopTasks: [DeviceIdentifier: Task<Void, Never>] = [:]
  var rumbleStopTokens = RumbleStopTokenRegistry()
  var physicalOutputOwnership = PhysicalOutputOwnership()
  /// Observed devices that did not bind, keyed by the connection that reported them.
  var unboundDevices: [UnboundDeviceKey: ApplicationServiceUnboundDevice] = [:]
  /// OJD's input claim on each rejected HID connection, keyed by connection ID.
  var unboundHIDClaims: [UUID: UnboundHIDClaim] = [:]
  /// HID connections left to macOS by native pass-through, keyed by connection ID.
  var passThroughDevices: [UUID: PassThroughHIDDevice] = [:]

  /// Creates a manager that sends all output to `dispatcher`.
  ///
  /// - Parameters:
  ///   - dispatcher: Output dispatcher for sending HID reports.
  ///   - virtualProfile: Virtual device profile for self-exclusion filtering.
  ///   - usbTransportProvider: Native raw-USB transport provider, or nil to disable raw USB
  ///     discovery.
  public init(
    dispatcher: any OutputDispatcher,
    virtualProfile: VirtualDeviceProfile = .default,
    usbTransportProvider: (any USBTransportProvider)? = nil,
    wirelessControllerDisconnector: (any WirelessControllerDisconnecting)? = nil
  ) {
    self.dispatcher = dispatcher
    self.usbTransportProvider = usbTransportProvider
    self.wirelessControllerDisconnector = wirelessControllerDisconnector
    let registry = ProtocolDriverRegistry()
    self.protocolDriverRegistry = registry
    self.permissionManager = PermissionManager()
    self.hidManager = HIDManager(
      virtualProfile: virtualProfile,
      additionalProfileIdentifiers: registry.hidIdentifiers,
      roleProfileIdentifiers: registry.hidRoleIdentifiers
    )
  }

  init(dispatcher: any OutputDispatcher, hidManager: HIDManager) {
    self.dispatcher = dispatcher
    self.usbTransportProvider = nil
    self.wirelessControllerDisconnector = nil
    self.protocolDriverRegistry = ProtocolDriverRegistry()
    self.permissionManager = PermissionManager()
    self.hidManager = hidManager
  }

  init(
    dispatcher: any OutputDispatcher,
    hidManager: HIDManager,
    usbTransportProvider: any USBTransportProvider
  ) {
    self.dispatcher = dispatcher
    self.usbTransportProvider = usbTransportProvider
    self.wirelessControllerDisconnector = nil
    self.protocolDriverRegistry = ProtocolDriverRegistry()
    self.permissionManager = PermissionManager()
    self.hidManager = hidManager
  }
}

extension DeviceManager {
  /// The session state of one connected controller; output routing checks it per input report.
  public func controllerSessionState(
    for identifier: DeviceIdentifier
  ) async -> ControllerSessionState? { await pipelines[identifier]?.controllerSessionState() }
}
