import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

extension AutomaticDispatcherCoordinatorTests {
  @Test(.timeLimit(.minutes(1)))
  func unavailableProfileSelectionNeverBuildsABackend() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let builds = AutomaticBuildCounter()
    let factory: AutomaticDispatcherCoordinator.Factory = { _ in
      _ = builds.next()
      return InstallationBackend(stage: .none, gate: InstallationGate())
    }

    try await coordinator.activateOne(
      identifier: identifier,
      descriptions: [description],
      isEligible: { _, _ in true },
      profileProvider: { _ in nil },
      factory: factory
    )
    try await coordinator.activate(
      identifiers: [identifier],
      descriptions: [description],
      isEligible: { _, _ in true },
      profileProvider: { _ in nil },
      factory: factory
    )

    #expect(builds.next() == 0)
    #expect(await coordinator.installedTargets().isEmpty)
    await coordinator.close()
  }
}
