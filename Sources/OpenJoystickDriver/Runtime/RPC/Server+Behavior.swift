import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import Security

extension ApplicationServiceServer {

  struct UserSpaceDispatcherBuild: Sendable {
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
    let status: String
    let closeSlot: CompatibilityBackendCloseSlot

    init(
      dispatcher: any CompatibilityUserSpaceOutputDispatching,
      status: String,
      closeSlot: CompatibilityBackendCloseSlot? = nil
    ) {
      self.dispatcher = dispatcher
      self.status = status
      self.closeSlot = closeSlot ?? CompatibilityBackendCloseSlot(dispatcher)
    }
  }

  public func stop() async {
    rpcServer?.stop()
    rpcServer = nil
    userSpaceLock.withLock { compatibilityServerStopped = true }
    await compatibilityTransitionCoordinator.stop()
    let identifiers = await connectedIdentifierProvider()
    _ = await feedbackGate.quiesceAndNeutralize(
      identifiers,
      timeout: compatibilityTransitionTimeouts.feedbackNanoseconds,
      clock: compatibilityTransitionClock
    )
    let slot = userSpaceLock.withLock { () -> CompatibilityBackendCloseSlot? in
      dispatcher.setBackend(nil)
      let slot = userSpaceCloseSlot
      userSpaceDispatcher = nil
      userSpaceCloseSlot = nil
      userSpaceEnabled = false
      userSpaceStatus = "off"
      return slot
    }
    _ = await closeCompatibilityBackend(slot)
  }

  static func isTrustedClient(processIdentifier: Int32) -> Bool {
    // The app's own UI calls this service over the socket. Security cannot resolve a running
    // process's code once its bundle is replaced on disk (a rebuild or an update before relaunch),
    // which would reject the app's own calls and freeze its controller list.
    if processIdentifier == getpid() { return true }
    guard let expected = currentProcessSigningIdentity else { return false }
    let attributes = [kSecGuestAttributePid as String: processIdentifier] as CFDictionary
    var guestCode: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guestCode) == errSecSuccess,
      let guestCode, let actual = signingIdentity(for: guestCode)
    else { return false }
    return actual == expected
  }

  /// This process's code does not change while it runs; every client connection compares with it.
  private static let currentProcessSigningIdentity = signingIdentityForCurrentProcess()

  private static func signingIdentityForCurrentProcess() -> SigningIdentity? {
    var currentCode: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &currentCode) == errSecSuccess, let currentCode else {
      return nil
    }
    return signingIdentity(for: currentCode)
  }

  private static func signingIdentity(for code: SecCode) -> SigningIdentity? {
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String
    else { return nil }
    return SigningIdentity(
      identifier: identifier,
      teamIdentifier: values[kSecCodeInfoTeamIdentifier as String] as? String
    )
  }

  private struct SigningIdentity: Equatable {
    let identifier: String
    let teamIdentifier: String?
  }

  // MARK: - Private

  func buildUserSpaceDispatcher() throws -> UserSpaceDispatcherBuild {
    if let userSpaceDispatcherBuilder {
      let dispatcher = try userSpaceDispatcherBuilder()
      return UserSpaceDispatcherBuild(dispatcher: dispatcher, status: dispatcher.status)
    }
    let overrides = virtualHIDProfileOverrides
    let automatic = AutomaticUserSpaceOutputDispatcher(
      deviceManager: deviceManager,
      builder: { [weak self] profileID in
        guard let self else { throw UserSpaceOutputDispatcher.CreationError.createFailed }
        return try self.buildAutomaticUserSpaceDispatcher(profileID: profileID)
      },
      overrideProvider: { overrides.override(vendorID: $0.vendorID, productID: $0.productID) }
    )
    return UserSpaceDispatcherBuild(dispatcher: automatic, status: automatic.status)
  }

  /// The automatic dispatcher applies ownership and session policy per controller, so each
  /// profile's backend publishes directly.
  private func buildAutomaticUserSpaceDispatcher(
    profileID: VirtualHIDProfileID
  ) throws -> any CompatibilityUserSpaceOutputDispatching {
    let profile = try profileID.makeProfile()
    return try makeUserSpaceOutputDispatcher(
      profile: profile.identity,
      format: profile.reportFormat
    )
  }

  private func makeUserSpaceOutputDispatcher(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat
  ) throws -> UserSpaceOutputDispatcher {
    let outputHandler: UserSpaceOutputDispatcher.OutputCommandHandler = {
      [weak self] identifier, command in
      guard let self else { return }
      self.feedbackGate.submit(identifier: identifier, command: command)
    }

    return try UserSpaceOutputDispatcher(
      profile: profile,
      format: format,
      onOutputCommand: outputHandler
    ) { [weak self] identifier in
      _ = await self?.feedbackGate.quiesceAndNeutralize(
        [identifier],
        timeout: self?.compatibilityTransitionTimeouts.feedbackNanoseconds
          ?? CompatibilityTransitionTimeouts.standard.feedbackNanoseconds,
        clock: self?.compatibilityTransitionClock ?? .system,
        resumeWhenComplete: true
      )
    }
  }

  func currentUserSpaceStatus() -> String {
    userSpaceLock.withLock {
      guard let dispatcher = userSpaceDispatcher else { return userSpaceStatus }
      let rumble: String
      if dispatcher.lastRumbleStatus == "none" {
        rumble = ""
      } else {
        rumble = ", rumble: \(dispatcher.lastRumbleStatus)"
      }
      let liveStatus = "\(dispatcher.status)\(rumble)"
      return userSpaceStatus.hasPrefix("error:")
        ? "\(userSpaceStatus); live: \(liveStatus)" : liveStatus
    }
  }

  struct UserSpaceStatusSnapshot: Sendable {
    let enabled: Bool
    let status: String
  }

  func userSpaceStatusSnapshot() -> UserSpaceStatusSnapshot {
    userSpaceLock.withLock {
      let status: String
      if userSpaceStatus.hasPrefix("error:"), let userSpaceDispatcher {
        status = "\(userSpaceStatus); live: \(userSpaceDispatcher.status)"
      } else if let userSpaceDispatcher, userSpaceDispatcher.lastRumbleStatus != "none" {
        status = "\(userSpaceDispatcher.status), rumble: \(userSpaceDispatcher.lastRumbleStatus)"
      } else if let userSpaceDispatcher {
        status = userSpaceDispatcher.status
      } else {
        status = userSpaceStatus
      }
      return UserSpaceStatusSnapshot(enabled: userSpaceEnabled, status: status)
    }
  }

  func isCompatibilityServerStopped() -> Bool {
    userSpaceLock.withLock { compatibilityServerStopped }
  }

  /// Closes the backend that `slot` owns within the candidate-close timeout; true when it closed.
  func closeCompatibilityBackend(_ slot: CompatibilityBackendCloseSlot?) async -> Bool {
    guard let slot else { return true }
    return await slot.close(
      timeout: compatibilityTransitionTimeouts.candidateCloseNanoseconds,
      clock: compatibilityTransitionClock
    )
  }
}
