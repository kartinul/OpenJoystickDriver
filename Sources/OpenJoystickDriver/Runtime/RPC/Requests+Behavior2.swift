import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {

  public func disconnectWirelessController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      let result = await deviceManager.disconnectWirelessController(
        vendorID: UInt16(clamping: vendorID),
        productID: UInt16(clamping: productID),
        runtimeIdentifier: runtimeIdentifier
      )
      callback.call((try? JSONEncoder().encode(result)) ?? Data())
    }
  }

  public func getVirtualDeviceDiagnostics(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    Task {
      let userSnapshot = userSpaceStatusSnapshot()
      let devices = VirtualDeviceDiagnostics.enumerateHIDGamepads()
      let payload = ApplicationServiceVirtualDeviceDiagnosticsPayload(
        userSpaceVirtualDeviceEnabled: userSnapshot.enabled,
        userSpaceVirtualDeviceStatus: userSnapshot.status,
        hidGamepads: devices
      )
      do { callback.call(try JSONEncoder().encode(payload)) } catch {
        print("[ApplicationServiceServer] getVirtualDeviceDiagnostics encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func runVirtualDeviceSelfTest(seconds: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let minimumDiagnosticDurationSeconds = 1
    let maximumDiagnosticDurationSeconds = 30
    let secs = max(minimumDiagnosticDurationSeconds, min(maximumDiagnosticDurationSeconds, seconds))
    Task {
      let payload = await runVirtualDeviceSelfTestInternal(seconds: secs)
      do { callback.call(try JSONEncoder().encode(payload)) } catch {
        print("[ApplicationServiceServer] runVirtualDeviceSelfTest encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func resetSettings(reply: @escaping (Bool) -> Void) {
    let callback = SendableReply(call: reply)
    Task { [weak self] in
      guard let self else { return }
      callback.call(await self.resetSettingsAsync())
    }
  }

  private func resetSettingsAsync() async -> Bool {
    await compatibilityTransitionCoordinator.enqueue { [weak self] in
      guard let self else { return false }
      return await self.performResetSettingsAsync()
    }
  }

  private func performResetSettingsAsync() async -> Bool {
    resetVirtualHIDProfileSettings()
    let live = await performCompatibilityBackendActivation()
    let retargeted = await retargetConnectedControllers()
    return live && retargeted
  }

  func getRemappingSnapshot(
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.snapshot()) }
  }

  func deleteDamagedRemappingProfile(
    _ arguments: ApplicationServiceRemappingProfileIssueArguments,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.deleteDamagedProfile(issueID: arguments.issueID)) }
  }

  func resetRemappingProfileLibrary(
    _ arguments: ApplicationServiceRemappingProfileIssueArguments,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.resetDamagedLibrary(issueID: arguments.issueID)) }
  }

  func remappingMotionCalibration(
    _ arguments: ApplicationServiceMotionCalibrationArguments,
    reply: @escaping (RemappingRequestResult<RemappingMotionCalibrationStatus>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.motionCalibration(arguments)) }
  }

  func pairRemappingJoyCons(
    _ arguments: ApplicationServiceJoyConPairArguments,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.pairJoyCons(arguments)) }
  }

  func unpairRemappingJoyCons(
    _ arguments: ApplicationServiceJoyConUnpairArguments,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.unpairJoyCons(arguments)) }
  }

  func getRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<RemappingProfile>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.profile(id: id)) }
  }

  func createRemappingProfile(
    _ profile: RemappingProfile,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.create(profile)) }
  }

  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      callback.call(await remappingRequests.update(profile, expectedCurrent: expectedCurrent))
    }
  }

  func importRemappingProfile(
    _ profile: RemappingProfile,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.importProfile(profile)) }
  }

  func deleteRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.delete(id: id)) }
  }

  func activateRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.activate(id: id)) }
  }

  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      callback.call(await remappingRequests.deactivate(vendorID: vendorID, productID: productID))
    }
  }

  func deactivateRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.deactivate(profileID: id)) }
  }

  func getRemappingPostEventAccess(
    reply: @escaping (RemappingRequestResult<RemappingPostEventAccessState>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.currentPostEventAccess()) }
  }

  func requestRemappingPostEventAccess(
    reply: @escaping (RemappingRequestResult<RemappingPostEventAccessState>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.requestPostEventAccess()) }
  }
}
