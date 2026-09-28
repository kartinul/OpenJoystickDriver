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

  func run() {
    switch action {
    case .resetAll: VirtualProfileResetAllCommand().run()
    case .change(let change, let selector): run(change, selector: selector)
    }
  }

  private func run(_ change: VirtualHIDProfileChange, selector: ControllerSelector) {
    do {
      let client = ApplicationServiceClient()
      client.connect()
      defer { client.disconnect() }
      let statusResult: Result<ApplicationServiceStatusPayload, Error> = runSyncResult {
        do { return .success(try await client.getStatus()) } catch { return .failure(error) }
      }
      let device = try selector.resolve(devices: try statusResult.get().connectedDevices)
      let mutation: Result<VirtualHIDProfileOverrideResult, Error> = runSyncResult {
        do {
          switch change {
          case .set(let profile):
            return .success(
              try await client.setVirtualHIDProfileOverride(
                profile.rawValue,
                vendorID: device.vendorID,
                productID: device.productID,
                runtimeIdentifier: device.runtimeIdentifier
              )
            )
          case .reset:
            return .success(
              try await client.resetVirtualHIDProfileOverride(
                vendorID: device.vendorID,
                productID: device.productID,
                runtimeIdentifier: device.runtimeIdentifier
              )
            )
          }
        } catch { return .failure(error) }
      }
      let result = try mutation.get()
      print(Self.liveText(result))
      if let failure = Self.failureText(result) {
        CLIOutput.error(failure)
        exit(1)
      }
    } catch {
      CLIOutput.error(error.localizedDescription)
      exit(1)
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
