import Foundation
import OpenJoystickDriverKit

/// Submits system-extension requests for the app's setup flow. The composition root adapts it to
/// the presentation layer's setup-client contract.
package final class DefaultSystemExtensionSetupClient: Sendable {
  package init() {}

  package func inspect() -> ExtensionStatus { ExtensionProbe.currentStatus() }

  package func requestActivation() async -> SystemExtensionSetupRequestResult {
    await request(.activation)
  }

  package func requestDeactivation() async -> SystemExtensionSetupRequestResult {
    await request(.deactivation)
  }

  private func request(
    _ mode: SystemExtensionSubmission.Mode
  ) async -> SystemExtensionSetupRequestResult {
    let requestState = SystemExtensionRequestState()
    return await withTaskCancellationHandler(
      operation: {
        await withCheckedContinuation { continuation in
          guard !Task.isCancelled else {
            continuation.resume(returning: SystemExtensionSetupRequestResult.cancelled)
            return
          }
          let submission = SystemExtensionSubmission(mode: mode) {
            continuation.resume(returning: $0)
          }
          guard requestState.start(submission) else {
            continuation.resume(returning: SystemExtensionSetupRequestResult.cancelled)
            return
          }
          let timeout = DispatchWorkItem { [weak submission] in submission?.timeout() }
          DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        }
      },
      onCancel: { requestState.cancel() }
    )
  }
}
