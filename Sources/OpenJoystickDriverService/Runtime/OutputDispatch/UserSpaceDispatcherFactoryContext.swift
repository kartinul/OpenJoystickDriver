import Foundation
import OpenJoystickDriverKit

/// Server-owned collaborators that a user-space dispatcher factory wires into what it builds.
struct UserSpaceDispatcherFactoryContext: Sendable {
  let deviceManager: DeviceManager
  let feedbackGate: VirtualOutputFeedbackGate
  let profileOverrides: VirtualHIDProfileOverrideStore
  let timeouts: VirtualOutputTransitionTimeouts
  let clock: VirtualOutputTransitionClock
}

/// Builds one user-space dispatcher candidate for `ApplicationServiceServer` to activate.
typealias UserSpaceDispatcherFactory =
  @Sendable (UserSpaceDispatcherFactoryContext) throws -> any VirtualOutputDispatching
