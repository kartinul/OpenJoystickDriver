import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// Records, in order, what each retarget probe was asked to do.
final class RetargetEventLog: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [String] = []
  private var backends: [RetargetBackendProbe] = []

  func record(_ event: String) { lock.withLock { events.append(event) } }
  func append(_ backend: RetargetBackendProbe) { lock.withLock { backends.append(backend) } }
  func snapshot() -> [String] { lock.withLock { events } }
  func built() -> [RetargetBackendProbe] { lock.withLock { backends } }
}

final class RetargetBackendProbe: VirtualOutputDispatching, RemappingGamepadSink,
  RemappingGamepadOutputControlling, @unchecked Sendable
{
  let profile: VirtualHIDProfileID
  private let log: RetargetEventLog
  private let failsActivation: Bool
  private let activationGate: InstallationGate?
  private let lock = NSLock()
  private var isClosed = false
  private var isOutputSuppressed = false
  private var isRemappingSuppressed = false
  var suppressOutput: Bool {
    get { lock.withLock { isOutputSuppressed } }
    set { lock.withLock { isOutputSuppressed = newValue } }
  }
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }
  var closed: Bool { lock.withLock { isClosed } }
  var remappingSuppressed: Bool { lock.withLock { isRemappingSuppressed } }

  init(
    profile: VirtualHIDProfileID,
    log: RetargetEventLog,
    failsActivation: Bool = false,
    activationGate: InstallationGate? = nil
  ) {
    self.profile = profile
    self.log = log
    self.failsActivation = failsActivation
    self.activationGate = activationGate
  }

  private func record(_ event: String) { log.record("\(profile.rawValue) \(event)") }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    record("activate \(identifiers.map(\.controllerIdentity.vendorID))")
    await activationGate?.suspend()
    if failsActivation { throw AutomaticBackendProbe.ActivationFailure() }
  }

  func setRemappingOutputSuppressed(_ suppressed: Bool) {
    lock.withLock { isRemappingSuppressed = suppressed }
  }

  func send(_ state: RemappingGamepadState, for _: DeviceIdentifier) {
    record(state == .neutral ? "neutral" : "state")
  }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}
  func activateOutput(for _: DeviceIdentifier) {}

  func close() {
    lock.withLock { isClosed = true }
    record("close")
  }
}

/// The Advanced override a test changes between selections.
final class ProfileOverrideBox: @unchecked Sendable {
  private let lock = NSLock()
  private var profiles: [UInt16: VirtualHIDProfileID] = [:]

  func set(_ profile: VirtualHIDProfileID?, vendorID: UInt16) {
    lock.withLock { profiles[vendorID] = profile }
  }

  func profile(for description: ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? {
    lock.withLock { profiles[description.vendorID] }
  }
}

/// Which step of building a replacement backend a test makes fail.
enum ProfileRetargetFailure: Sendable { case build, activation }
