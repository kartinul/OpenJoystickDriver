import Foundation
import OpenJoystickDriverKit

/// `controller virtual set|reset`: stores or clears the virtual HID profile override of the
/// selected controller's model. `reset --all` instead delegates to
/// `VirtualProfileResetAllCommand`, which clears every controller's override.
///
/// When the application service applies the request but reports a failure, the command still
/// prints the live profile line to stdout, then prints the failure to stderr and exits with 1.
struct VirtualProfileCommand {
  let action: CLIVirtualProfileAction

  func run() async throws {
    switch action {
    case .resetAll: try await VirtualProfileResetAllCommand().run()
    case .change(let change, let selector): try await run(change, selector: selector)
    }
  }

  private func run(_ change: VirtualHIDProfileChange, selector: ControllerSelector) async throws {
    let failure: String?
    do {
      let client = ApplicationServiceClient()
      await client.connect()
      defer { client.disconnect() }
      let device = try selector.resolve(devices: try await client.getStatus().connectedDevices)
      let result: VirtualHIDProfileOverrideResult
      switch change {
      case .set(let profile):
        result = try await client.setVirtualHIDProfileOverride(
          profile.rawValue,
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
      case .reset:
        result = try await client.resetVirtualHIDProfileOverride(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
      }
      print(Self.liveText(result))
      failure = Self.failureText(result)
    } catch {
      CLIOutput.error(error.localizedDescription)
      throw CLIExit.failure
    }
    if let failure {
      CLIOutput.error(failure)
      throw CLIExit.failure
    }
  }

  static func liveText(_ result: VirtualHIDProfileOverrideResult) -> String {
    guard let live = result.live else {
      return CLILocalized.format(
        "cli.controller.virtual.none",
        "Virtual HID profile: none (%@)",
        result.source
      )
    }
    return CLILocalized.format(
      "cli.controller.virtual.live",
      "Virtual HID profile: %@ (%@)",
      live.rawValue,
      result.source
    )
  }

  static func failureText(_ result: VirtualHIDProfileOverrideResult) -> String? {
    guard let failure = result.failure else { return nil }
    var reason = failure.code
    if case .activationFailed(let detail) = failure { reason += ": \(detail)" }
    return CLILocalized.format(
      "cli.controller.virtual.failed",
      "Virtual HID profile request failed: %@",
      reason
    )
  }

  /// A `controller virtual set` profile argument that names no virtual HID profile.
  struct UnknownProfile: LocalizedError, Equatable {
    let value: String

    var errorDescription: String? {
      CLILocalized.format(
        "cli.controller.virtual.unknown_profile",
        "Unknown virtual HID profile '%@'. Use one of: %@.",
        value,
        VirtualHIDProfileID.allCases.map(\.rawValue).joined(separator: ", ")
      )
    }
  }

  /// A `controller virtual set` command that names no virtual HID profile.
  struct MissingProfile: LocalizedError, Equatable {
    var errorDescription: String? {
      CLILocalized.format(
        "cli.controller.virtual.missing_profile",
        "'controller virtual set' requires a virtual HID profile. Use one of: %@.",
        VirtualHIDProfileID.allCases.map(\.rawValue).joined(separator: ", ")
      )
    }
  }

  /// A `controller virtual reset --all` command that also names a controller selector.
  struct ResetAllWithSelector: LocalizedError, Equatable {
    var errorDescription: String? {
      CLILocalized.text(
        "cli.controller.virtual.reset_all_with_selector",
        "'--all' cannot be combined with --vid, --pid, or --device."
      )
    }
  }
}
