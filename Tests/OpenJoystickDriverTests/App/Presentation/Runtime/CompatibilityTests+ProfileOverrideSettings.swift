import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

extension CompatibilityTests {
  @Test
  func anOverrideChangeAndASettingsResetRunOneAtATime() async throws {
    let gate = InstallationGate()
    let fixture = try await profileOverrideServer(activationGate: (.generic, gate))
    let resetFinished = CompletionFlag()

    let server = fixture.server
    let set = Task {
      await server.changeVirtualHIDProfileOverride(
        .set("hid-generic"),
        vendorID: 1,
        productID: 2,
        runtimeIdentifier: nil
      )
    }
    await gate.waitForEntry()
    let reset = Task {
      let reset = await withCheckedContinuation { continuation in
        server.resetSettings { continuation.resume(returning: $0) }
      }
      resetFinished.mark()
      return reset
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(!resetFinished.isMarked)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .generic)
    await gate.release()
    #expect(await set.value.live == .generic)
    #expect(await reset.value)
    #expect(fixture.defaults.object(forKey: VirtualHIDProfileOverrideStore.defaultsKey) == nil)
    let state = fixture.server.automaticUserSpaceDispatcher()?.profileState(
      runtimeIdentifier: DeviceIdentifier(vendorID: 1, productID: 2).runtimeIdentifier
    )
    #expect(state?.selection?.profileID == .xboxOneSBluetooth)
    await fixture.tearDown()
  }

  @Test
  func aHangingRetargetDuringResetSettingsTimesOut() async throws {
    let gate = InstallationGate()
    let fixture = try await profileOverrideServer(
      activationGate: (.xboxOneSBluetooth, gate),
      timeouts: CompatibilityTransitionTimeouts(
        stageNanoseconds: 2_000_000_000,
        perControllerNanoseconds: 50_000_000,
        totalNanoseconds: 10_000_000_000
      )
    ) { VirtualHIDProfileOverrideStore(defaults: $0).setGenericForTest() }
    let resetFinished = CompletionFlag()
    let server = fixture.server

    let reset = Task {
      let reset = await withCheckedContinuation { continuation in
        server.resetSettings { continuation.resume(returning: $0) }
      }
      resetFinished.mark()
      return reset
    }
    await gate.waitForEntry()
    try await Task.sleep(nanoseconds: 1_000_000_000)

    #expect(resetFinished.isMarked)
    await gate.release()
    #expect(await reset.value == false)
    #expect(fixture.defaults.object(forKey: VirtualHIDProfileOverrideStore.defaultsKey) == nil)
    await fixture.tearDown()
  }

  @Test
  func aLateRetargetReselectsOnlyAfterEarlierQueuedChanges() async throws {
    let gate = InstallationGate()
    let fixture = try await profileOverrideServer(
      activationGate: (.xboxOneSBluetooth, gate),
      timeouts: CompatibilityTransitionTimeouts(
        stageNanoseconds: 2_000_000_000,
        perControllerNanoseconds: 50_000_000,
        totalNanoseconds: 10_000_000_000
      )
    ) { VirtualHIDProfileOverrideStore(defaults: $0).setGenericForTest() }
    let result = await fixture.change(.set("hid-xbox-one-s-bt"))
    guard case .activationFailed = result.failure else {
      Issue.record("Expected activation-failed, got \(String(describing: result.failure))")
      return
    }
    let blocker = InstallationGate()
    let coordinator = fixture.server.compatibilityTransitionCoordinator
    let queued = Task {
      await coordinator.enqueue { @Sendable in
        await blocker.suspend()
        return true
      }
    }
    await blocker.waitForEntry()

    await gate.release()
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(fixture.log.built().map(\.profile) == [.generic, .xboxOneSBluetooth])

    await blocker.release()
    #expect(await queued.value)
    for _ in 0..<200 where fixture.log.built().count < 3 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(fixture.log.built().map(\.profile) == [.generic, .xboxOneSBluetooth, .generic])
    await fixture.tearDown()
  }

  @Test
  func statusReportsEachControllersProfileAndTheStoredOverride() async throws {
    let id = DeviceIdentifier(vendorID: 1, productID: 2)
    let fixture = try await profileOverrideServer([id])
    _ = await fixture.change(.set("hid-generic"))

    let devices = fixture.server.describingVirtualHIDProfiles([
      description(id), description(DeviceIdentifier(vendorID: 5, productID: 6)),
    ])

    #expect(
      devices.map(\.virtualHIDProfile) == [
        ApplicationServiceVirtualHIDProfileStatus(
          profile: .generic,
          source: "override",
          override: .generic,
          unavailable: false
        ),
        ApplicationServiceVirtualHIDProfileStatus(
          profile: nil,
          source: nil,
          override: nil,
          unavailable: false
        ),
      ]
    )
    await fixture.tearDown()
  }

  @Test
  func statusSurfacesUnreadableOverridesAndTheRetiredIdentity() async throws {
    let stored = Data(#"[{"vendorID":1,"productID":2,"profile":"xone-hid"}]"#.utf8)
    let fixture = try await profileOverrideServer {
      $0.set(stored, forKey: VirtualHIDProfileOverrideStore.defaultsKey)
      $0.set("xone-hid", forKey: VirtualHIDProfileOverrideStore.legacyCompatibilityIdentityKey)
    }

    let data = await withCheckedContinuation { continuation in
      fixture.server.getStatus { continuation.resume(returning: $0) }
    }
    let status = try JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)

    #expect(status.virtualHIDProfileOverrideError == "unsupported-value: xone-hid")
    #expect(status.legacyCompatibilityIdentityRejected == "xone-hid")
    let result = await fixture.change(.set("hid-generic"))
    #expect(result.failure == .persistenceFailed)
    #expect(result.live == .xboxOneSBluetooth)
    await fixture.tearDown()
  }

  @Test
  func resetSettingsClearsOverridesAndRetiredSettings() async throws {
    let retiredKeys = [
      VirtualHIDProfileOverrideStore.legacyCompatibilityIdentityKey,
      ApplicationServiceServer.legacyCompatibilityRetrySnapshotDefaultsKey,
    ]
    let fixture = try await profileOverrideServer {
      $0.set("xone-hid", forKey: retiredKeys[0])
      $0.set(Data(), forKey: retiredKeys[1])
    }
    _ = await fixture.change(.set("hid-generic"))

    let reset = await withCheckedContinuation { continuation in
      fixture.server.resetSettings { continuation.resume(returning: $0) }
    }

    #expect(reset)
    #expect(fixture.defaults.object(forKey: VirtualHIDProfileOverrideStore.defaultsKey) == nil)
    for key in retiredKeys { #expect(fixture.defaults.object(forKey: key) == nil) }
    let state = fixture.server.automaticUserSpaceDispatcher()?.profileState(
      runtimeIdentifier: DeviceIdentifier(vendorID: 1, productID: 2).runtimeIdentifier
    )
    #expect(state?.selection?.profileID == .xboxOneSBluetooth)
    await fixture.tearDown()
  }

  @Test(arguments: ["automatic", nil] as [String?])
  func statusReportsAnyStoredRetiredIdentityUntilReset(stored: String?) async throws {
    let fixture = try await profileOverrideServer {
      $0.set(stored, forKey: VirtualHIDProfileOverrideStore.legacyCompatibilityIdentityKey)
    }

    #expect(try await status(fixture.server).legacyCompatibilityIdentityRejected == stored)
    let reset = await withCheckedContinuation { continuation in
      fixture.server.resetSettings { continuation.resume(returning: $0) }
    }
    #expect(reset)
    #expect(try await status(fixture.server).legacyCompatibilityIdentityRejected == nil)
    await fixture.tearDown()
  }

  private func status(
    _ server: ApplicationServiceServer
  ) async throws -> ApplicationServiceStatusPayload {
    let data = await withCheckedContinuation { continuation in
      server.getStatus { continuation.resume(returning: $0) }
    }
    return try JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
  }

  @Test
  func profileOverridePayloadsRoundTrip() throws {
    let results = [
      VirtualHIDProfileOverrideResult(
        requested: .generic,
        live: .xboxOneSBluetooth,
        source: "automatic-after-rejecting",
        failure: .overrideRejectedByController
      ),
      VirtualHIDProfileOverrideResult(
        requested: .xboxOneSBluetooth,
        live: .generic,
        source: "override",
        failure: .activationFailed(detail: "backend unavailable")
      ),
      VirtualHIDProfileOverrideResult(requested: nil, live: nil, source: "automatic", failure: nil),
    ]
    for result in results {
      let data = try JSONEncoder().encode(result)
      #expect(try JSONDecoder().decode(VirtualHIDProfileOverrideResult.self, from: data) == result)
    }
    let failures: [VirtualHIDProfileOverrideFailure] = [
      .unknownProfile, .controllerNotFound, .overrideRejectedByController,
      .activationFailed(detail: "x"), .outputDisabled, .serverStopped, .persistenceFailed,
    ]
    let codes = try failures.map { failure in
      let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(failure))
      return (object as? [String: String])?["code"]
    }
    #expect(
      codes == [
        "unknown-profile", "controller-not-found", "override-rejected-by-controller",
        "activation-failed", "output-disabled", "server-stopped", "persistence-failed",
      ]
    )
    let requested = try JSONEncoder().encode(results[0])
    let object = try JSONSerialization.jsonObject(with: requested) as? [String: Any]
    #expect(object?["requested"] as? String == "hid-generic")

    let status = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: "override",
      override: .generic,
      unavailable: false
    )
    let statusData = try JSONEncoder().encode(status)
    #expect(
      try JSONDecoder().decode(ApplicationServiceVirtualHIDProfileStatus.self, from: statusData)
        == status
    )
  }
}

/// Whether an asynchronous request has finished.
private final class CompletionFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var marked = false

  var isMarked: Bool { lock.withLock { marked } }
  func mark() { lock.withLock { marked = true } }
}
