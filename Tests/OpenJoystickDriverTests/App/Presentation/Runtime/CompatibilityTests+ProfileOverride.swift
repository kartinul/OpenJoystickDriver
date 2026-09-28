import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

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

final class RetargetBackendProbe: CompatibilityUserSpaceOutputDispatching, RemappingGamepadSink,
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
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }
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

extension CompatibilityTests {
  private struct BuildFailure: Error {}

  private func retargetDispatcher(
    _ identifiers: [DeviceIdentifier],
    overrides: ProfileOverrideBox,
    log: RetargetEventLog,
    failure: (VirtualHIDProfileID, ProfileRetargetFailure)? = nil,
    gate: (VirtualHIDProfileID, InstallationGate)? = nil
  ) -> AutomaticUserSpaceOutputDispatcher {
    let overrideProvider: @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? =
      { overrides.profile(for: $0) }
    return AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { profile in
        if let failure, failure.0 == profile, failure.1 == .build { throw BuildFailure() }
        let backend = RetargetBackendProbe(
          profile: profile,
          log: log,
          failsActivation: failure.map { $0.0 == profile && $0.1 == .activation } ?? false,
          activationGate: gate.flatMap { $0.0 == profile ? $0.1 : nil }
        )
        log.append(backend)
        return backend
      },
      descriptionsProvider: provider(identifiers.map { description($0) }),
      overrideProvider: overrideProvider
    )
  }

  @Test
  func profileOverrideChangesTheBuiltProfile() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    overrides.set(.generic, vendorID: 1)
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)

    try await dispatcher.activate(for: [id])

    #expect(log.built().map(\.profile) == [.generic])
    #expect(dispatcher.selectionSource(for: id) == .override)
    #expect(dispatcher.status.contains("targets: hid-generic"))
    await dispatcher.close()
  }

  @Test
  func retargetRebuildsOnlyTheTargetController() async throws {
    let first = DeviceIdentifier(vendorID: 1, productID: 2)
    let second = DeviceIdentifier(vendorID: 3, productID: 4)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([first, second], overrides: overrides, log: log)
    try await dispatcher.activate(for: [first, second])
    #expect(dispatcher.selectionSource(for: first) == .automatic)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: first)

    let built = log.built()
    #expect(built.map(\.profile) == [.xboxOneSBluetooth, .xboxOneSBluetooth, .generic])
    #expect(built.map(\.closed) == [true, false, false])
    #expect(dispatcher.selectionSource(for: first) == .override)
    #expect(dispatcher.selectionSource(for: second) == .automatic)
    #expect(dispatcher.status.contains("targets: hid-generic; hid-xbox-one-s-bt"))
    await dispatcher.close()
  }

  @Test
  func retargetActivatesTheReplacementThenNeutralizesBeforeRetiring() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(
      log.snapshot() == [
        "hid-xbox-one-s-bt activate [1]", "hid-generic activate [1]", "hid-xbox-one-s-bt neutral",
        "hid-xbox-one-s-bt close",
      ]
    )
    await dispatcher.close()
  }

  @Test(arguments: [ProfileRetargetFailure.build, .activation])
  func failedRetargetKeepsThePriorBackend(failure: ProfileRetargetFailure) async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher(
      [id],
      overrides: overrides,
      log: log,
      failure: (.generic, failure)
    )
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    await #expect(throws: (any Error).self) { try await dispatcher.retarget(controller: id) }

    let built = log.built()
    #expect(built.first?.profile == .xboxOneSBluetooth)
    #expect(built.first?.closed == false)
    #expect(built.dropFirst().allSatisfy { $0.closed })
    #expect(!log.snapshot().contains("hid-xbox-one-s-bt neutral"))
    #expect(dispatcher.status.contains("targets: hid-xbox-one-s-bt"))
    #expect(dispatcher.selectionSource(for: id) == .automatic)

    // Later reports keep publishing through the prior backend instead of retrying the override.
    await dispatcher.activateOutput(for: id)
    await dispatcher.activateOutput(for: id)
    #expect(log.built().count == built.count)
    #expect(log.built().first?.closed == false)
    await dispatcher.close()
  }

  @Test
  func dispatchAfterAnOverrideChangeKeepsTheBackendUntilRetarget() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    await dispatcher.activateOutput(for: id)
    try await dispatcher.activate(controller: id)

    #expect(log.built().map(\.profile) == [.xboxOneSBluetooth])
    #expect(log.built().first?.closed == false)
    #expect(dispatcher.selectionSource(for: id) == .automatic)

    try await dispatcher.retarget(controller: id)

    #expect(log.built().map(\.profile) == [.xboxOneSBluetooth, .generic])
    #expect(log.snapshot().contains("hid-xbox-one-s-bt neutral"))
    await dispatcher.close()
  }

  @Test
  func retargetCarriesRemappingSuppressionToTheReplacement() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    await dispatcher.setRemappingOutputSuppressed(true)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(log.built().last?.profile == .generic)
    #expect(log.built().last?.remappingSuppressed == true)
    await dispatcher.close()
  }

  @Test
  func retargetWhileSuppressedPublishesTheNewProfileOnResume() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    await dispatcher.setOutputSuppressed(true)
    #expect(log.built().first?.closed == true)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)
    #expect(log.built().count == 1)
    #expect(dispatcher.selectionSource(for: id) == .override)

    await dispatcher.setOutputSuppressed(false)

    #expect(log.built().map(\.profile) == [.xboxOneSBluetooth, .generic])
    #expect(log.built().last?.suppressOutput == false)
    await dispatcher.activateOutput(for: id)
    #expect(log.built().count == 2)
    #expect(dispatcher.status.contains("targets: hid-generic"))
    await dispatcher.close()
  }

  @Test
  func retargetOfAStoppedControllerBuildsNothingAndTheNextSessionUsesTheOverride() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])
    await dispatcher.controllerDidStop(id)

    overrides.set(.generic, vendorID: 1)
    try await dispatcher.retarget(controller: id)
    #expect(log.built().count == 1)

    try await dispatcher.activate(controller: id)

    #expect(log.built().map(\.profile) == [.xboxOneSBluetooth, .generic])
    await dispatcher.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func stoppingDuringAnInFlightRetargetKeepsNoSelectionOrBackend() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let gate = InstallationGate()
    let dispatcher = retargetDispatcher(
      [id],
      overrides: overrides,
      log: log,
      gate: (.generic, gate)
    )
    try await dispatcher.activate(for: [id])

    overrides.set(.generic, vendorID: 1)
    let retarget = Task { try await dispatcher.retarget(controller: id) }
    await gate.waitForEntry()
    let stop = Task { await dispatcher.controllerDidStop(id) }
    await gate.waitForCancellation()
    await gate.release()
    await stop.value

    await #expect(throws: (any Error).self) { try await retarget.value }
    #expect(log.built().map(\.profile) == [.xboxOneSBluetooth, .generic])
    #expect(log.built().allSatisfy { $0.closed })
    #expect(dispatcher.selectionSource(for: id) == nil)
    #expect(!dispatcher.status.contains("targets"))
    await dispatcher.close()
  }

  @Test
  func retargetWithAnUnchangedProfileIsANoOp() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let overrides = ProfileOverrideBox()
    let log = RetargetEventLog()
    let dispatcher = retargetDispatcher([id], overrides: overrides, log: log)
    try await dispatcher.activate(for: [id])

    overrides.set(.xboxOneSBluetooth, vendorID: 1)
    try await dispatcher.retarget(controller: id)

    #expect(log.snapshot() == ["hid-xbox-one-s-bt activate [1]"])
    #expect(dispatcher.selectionSource(for: id) == .override)
    await dispatcher.close()
  }
}
