import Foundation
import OpenJoystickDriverKit

extension PhysicalOutputCommand {
  /// A localized CLI message: its catalog key and English fallback.
  internal struct Message {
    let key: String
    let english: String
  }

  /// Sends `command` to `device` through the application service and fails with `unsupported`
  /// when the controller lacks the capability, or with `failed` for any other outcome that did
  /// not deliver the command. The daemon decides support; the CLI does not pre-check it.
  @discardableResult
  internal func sendOutput(
    _ command: ControllerOutputCommand,
    to device: ApplicationServiceDeviceDescription,
    unsupported: Message,
    failed: Message
  ) -> ControllerOutputResult {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let result: ControllerOutputResult? = runSyncOptionalResult(
      timeout: applicationServiceCallTimeoutSeconds
    ) {
      try? await client.sendControllerOutput(
        command,
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
    }
    guard let result, result.isDelivered else {
      guard result?.outcome == .unsupportedCapability else {
        fail(CLILocalized.text(failed.key, failed.english))
      }
      fail(CLILocalized.text(unsupported.key, unsupported.english))
    }
    return result
  }

  /// A warning for each requested trigger motor the controller lacks. Main-motor requests are
  /// mirrored onto the Steam trackpad haptics, so a dropped main or haptic channel is expected on
  /// every controller that has only one of the two and is not reported.
  internal func droppedTriggerMotorMessages(_ result: ControllerOutputResult) -> [String] {
    result.droppedRumbleChannels.compactMap { channel in
      switch channel {
      case .leftTrigger:
        CLILocalized.text(
          "cli.controller.noLeftTriggerMotor",
          "The selected controller does not expose a left trigger motor."
        )
      case .rightTrigger:
        CLILocalized.text(
          "cli.controller.noRightTriggerMotor",
          "The selected controller does not expose a right trigger motor."
        )
      case .leftMain, .rightMain, .leftHaptic, .rightHaptic: nil
      }
    }
  }
}
