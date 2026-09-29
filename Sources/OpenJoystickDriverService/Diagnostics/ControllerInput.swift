import OpenJoystickDriverKit

/// Shared application-service surface for CLI controller-input diagnostics.
package actor ControllerInputDiagnosticService {
  private let client: ApplicationServiceClient

  package init(client: ApplicationServiceClient = ApplicationServiceClient()) async {
    self.client = client
    await client.connect()
  }

  package func disconnect() { client.disconnect() }

  package func connectedDevices() async throws -> [ApplicationServiceDeviceDescription] {
    try await client.getStatus().connectedDevices
  }

  package func controllerState(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> ControllerState? {
    try await client.controllerState(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  package func packetLog(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> [PacketLogEntry] {
    try await client.packetLog(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier
    )
  }
}
