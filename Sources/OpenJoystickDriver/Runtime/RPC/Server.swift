import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import Security

/// Wraps a non-Sendable asynchronous reply closure so it can cross Task boundary.
///
/// Safe because each local RPC request completes its reply exactly once.
struct SendableReply<T>: @unchecked Sendable { let call: (T) -> Void }

/// Owns runtime state and serves authenticated local RPC requests.
///
/// Call start() once; listener lives for process lifetime.
/// - Note: @unchecked Sendable: ApplicationServiceServer is thread-safe -
///   actor-isolated DeviceManager/PermissionManager handle
///   their own synchronization; reply blocks are dispatched
///   by the local RPC bridge.
@objc
public final class ApplicationServiceServer: NSObject, @unchecked Sendable {
  let deviceManager: DeviceManager
  let permissionManager: PermissionManager
  let dispatcher: CompatibilityOutputDispatcher
  let remappingProfileLibrary: RemappingProfileLibrary
  let remappingRouter: RemappingOutputRouter
  let postEventAccess: CoreGraphicsPostEventAccess
  let remappingRequests: RemappingRequestCoordinator
  let compatibilityTransitionCoordinator = CompatibilityTransitionCoordinator()
  let compatibilityTransitionTimeouts: CompatibilityTransitionTimeouts
  let compatibilityTransitionClock: CompatibilityTransitionClock
  let connectedIdentifierProvider: @Sendable () async -> [DeviceIdentifier]
  let feedbackGate: CompatibilityFeedbackGate
  /// Service settings storage; also backs `virtualHIDProfileOverrides`.
  let defaults: UserDefaults
  let virtualHIDProfileOverrides: VirtualHIDProfileOverrideStore
  let userSpaceDispatcherBuilder:
    (@Sendable () throws -> any CompatibilityUserSpaceOutputDispatching)?
  let userSpaceLock = NSLock()
  var userSpaceDispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  var userSpaceEnabled: Bool
  var userSpaceStatus: String = "off"
  var userSpaceCloseSlot: CompatibilityBackendCloseSlot?
  var rpcServer: LocalServiceRPCServer?
  var compatibilityServerStopped = false
  /// Retired setting that `resetSettings` removes; nothing reads it.
  static let legacyCompatibilityRetrySnapshotDefaultsKey = "CompatibilityRetrySnapshot"

  /// Creates a server backed by the device manager, permissions, and output dispatchers.
  init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: CompatibilityOutputDispatcher,
    remappingProfileLibrary: RemappingProfileLibrary,
    remappingRouter: RemappingOutputRouter,
    postEventAccess: CoreGraphicsPostEventAccess,
    userSpaceDispatcherBuilder: (
      @Sendable () throws -> any CompatibilityUserSpaceOutputDispatching
    )? = nil,
    connectedIdentifierProvider: (@Sendable () async -> [DeviceIdentifier])? = nil,
    compatibilityTransitionTimeouts: CompatibilityTransitionTimeouts = .standard,
    compatibilityTransitionClock: CompatibilityTransitionClock = .system,
    defaults: UserDefaults = .standard
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.remappingProfileLibrary = remappingProfileLibrary
    self.remappingRouter = remappingRouter
    self.postEventAccess = postEventAccess
    self.remappingRequests = RemappingRequestCoordinator(
      library: remappingProfileLibrary,
      router: remappingRouter,
      postEventAccess: postEventAccess
    )
    self.userSpaceDispatcherBuilder = userSpaceDispatcherBuilder
    self.connectedIdentifierProvider =
      connectedIdentifierProvider ?? { await deviceManager.activeDeviceIdentifiers() }
    self.compatibilityTransitionTimeouts = compatibilityTransitionTimeouts
    self.compatibilityTransitionClock = compatibilityTransitionClock
    self.feedbackGate = CompatibilityFeedbackGate(deviceManager: deviceManager)
    self.defaults = defaults
    self.virtualHIDProfileOverrides = VirtualHIDProfileOverrideStore(defaults: defaults)
    self.userSpaceEnabled = false
    self.userSpaceCloseSlot = nil
    super.init()
  }

  /// Starts the authenticated local RPC server used by the headless host and CLI.
  public func start() throws {
    let server = LocalServiceRPCServer(authentication: Self.isTrustedClient(processIdentifier:)) {
      [weak self] request, completion in
      guard let self else {
        completion(LocalServiceRPCResponse(result: nil, error: "Service stopped."))
        return
      }
      self.handleLocalRPC(request, completion: completion)
    }
    try server.start()
    rpcServer = server
    print("[ApplicationServiceServer] Listening on authenticated local RPC socket")
  }
}
