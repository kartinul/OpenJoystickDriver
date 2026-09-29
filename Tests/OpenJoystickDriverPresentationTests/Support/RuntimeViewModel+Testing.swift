import OpenJoystickDriverKit

@testable import OpenJoystickDriverPresentation

extension RuntimeViewModel {
  /// Builds a view model whose System Extension setup uses a test client instead of the system.
  convenience init(gateway: any ApplicationServiceGateway) {
    self.init(
      gateway: gateway,
      systemExtensionSetup: SystemExtensionSetupCoordinator(
        client: FakeSetupClient(
          status: ExtensionStatus(bundle: .present, registration: .inactive("inactive"))
        )
      )
    )
  }
}
