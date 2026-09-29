import Foundation
import OpenJoystickDriverKit

typealias RemappingRequestResult<Value: Sendable> = Result<
  Value, ApplicationServiceRemappingRPCError
>

/// Serializes profile mutations, route refreshes, and the snapshot returned to RPC clients.
actor RemappingRequestCoordinator {
  static let maximumRuntimeIdentifierBytes = 512
  typealias MutationResponseAcceptanceHook =
    @Sendable (ApplicationServiceRemappingSnapshotPayload) async throws -> Void

  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  let postEventAccess: CoreGraphicsPostEventAccess
  let maximumResponseBytes: Int
  let maximumTransportFrameBytes: Int
  let beforeMutationResponseAcceptance: MutationResponseAcceptanceHook
  var operationTail: (id: UUID, task: Task<Void, Never>)?

  init(
    library: RemappingProfileLibrary,
    router: RemappingOutputRouter,
    postEventAccess: CoreGraphicsPostEventAccess,
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes,
    maximumTransportFrameBytes: Int = ApplicationServiceRemappingRPC.maximumTransportFrameBytes,
    beforeMutationResponseAcceptance: @escaping MutationResponseAcceptanceHook = { _ in }
  ) {
    self.library = library
    self.router = router
    self.postEventAccess = postEventAccess
    self.maximumResponseBytes = maximumResponseBytes
    self.maximumTransportFrameBytes = maximumTransportFrameBytes
    self.beforeMutationResponseAcceptance = beforeMutationResponseAcceptance
  }
}
