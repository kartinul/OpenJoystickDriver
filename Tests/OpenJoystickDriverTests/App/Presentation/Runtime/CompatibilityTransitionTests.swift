import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

actor CompatibilityTransitionGate {
  private var opened = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if opened { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    opened = true
    let pending = waiters
    waiters.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

actor CompatibilityFeedbackProbe {
  private var commands: [ControllerOutputCommand] = []

  func append(_ command: ControllerOutputCommand) { commands.append(command) }
  func count() -> Int { commands.count }
  func values() -> [ControllerOutputCommand] { commands }
}

final class CompatibilityTransitionProbe: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, @unchecked Sendable
{
  struct ActivationFailure: Error, Sendable {}

  let activationGate: CompatibilityTransitionGate?
  let failsActivation: Bool
  private let lock = NSLock()
  private var closeCount = 0
  private var activations: [[DeviceIdentifier]] = []

  init(activationGate: CompatibilityTransitionGate? = nil, failsActivation: Bool = false) {
    self.activationGate = activationGate
    self.failsActivation = failsActivation
  }

  var closeCountValue: Int { lock.withLock { closeCount } }
  var activationValues: [[DeviceIdentifier]] { lock.withLock { activations } }
  var suppressOutput = false
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    lock.withLock { activations.append(identifiers) }
    await activationGate?.wait()
    if failsActivation { throw ActivationFailure() }
  }

  func activate(controller identifier: DeviceIdentifier) async throws {
    try await activate(for: [identifier])
  }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}
  func activateOutput(for _: DeviceIdentifier) {}
  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
  func close() { lock.withLock { closeCount += 1 } }
}

final class CompatibilityTransitionFactory: @unchecked Sendable {
  struct BuildFailure: Error, Sendable {}

  private let lock = NSLock()
  private var probes: [CompatibilityTransitionProbe] = []
  private var failsBuild = false
  private var failsActivation = false
  private var gate: CompatibilityTransitionGate?

  var buildFails: Bool {
    get { lock.withLock { failsBuild } }
    set { lock.withLock { failsBuild = newValue } }
  }
  var activationFails: Bool {
    get { lock.withLock { failsActivation } }
    set { lock.withLock { failsActivation = newValue } }
  }
  var firstActivationGate: CompatibilityTransitionGate? {
    get { lock.withLock { gate } }
    set { lock.withLock { gate = newValue } }
  }

  func make() throws -> any CompatibilityUserSpaceOutputDispatching {
    try lock.withLock { () throws -> CompatibilityTransitionProbe in
      if failsBuild { throw BuildFailure() }
      let probe = CompatibilityTransitionProbe(
        activationGate: probes.isEmpty ? gate : nil,
        failsActivation: failsActivation
      )
      probes.append(probe)
      return probe
    }
  }

  func values() -> [CompatibilityTransitionProbe] { lock.withLock { probes } }

  func waitForCount(_ count: Int) async {
    while lock.withLock({ probes.count }) < count { await Task.yield() }
  }
}

/// A server with no live output whose backends come from `factory`, over isolated defaults.
struct CompatibilityTransitionFixture {
  let server: ApplicationServiceServer
  let defaults: UserDefaults
  let suiteName: String

  init(
    factory: CompatibilityTransitionFactory,
    identifiers: [DeviceIdentifier],
    timeouts: CompatibilityTransitionTimeouts = .standard,
    clock: CompatibilityTransitionClock = .system
  ) throws {
    suiteName = "OpenJoystickDriverTests.CompatibilityTransition.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suiteName))
    let compatibilityDispatcher = CompatibilityOutputDispatcher()
    let profileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      compatibility: compatibilityDispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: remappingRouter),
      permissionManager: PermissionManager(),
      dispatcher: compatibilityDispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      userSpaceDispatcherBuilder: { try factory.make() },
      connectedIdentifierProvider: { identifiers },
      compatibilityTransitionTimeouts: timeouts,
      compatibilityTransitionClock: clock,
      defaults: defaults
    )
  }

  /// Installs `backend` as the live output, as a successful earlier activation would.
  func installLive(_ backend: CompatibilityTransitionProbe) {
    server.userSpaceLock.withLock {
      server.userSpaceDispatcher = backend
      server.userSpaceCloseSlot = CompatibilityBackendCloseSlot(backend)
      server.userSpaceEnabled = true
      server.userSpaceStatus = backend.status
      server.dispatcher.setBackend(backend)
    }
  }

  func tearDown() async {
    await server.stop()
    defaults.removePersistentDomain(forName: suiteName)
  }
}

@Suite(.serialized)
struct CompatibilityTransitionTests {}
