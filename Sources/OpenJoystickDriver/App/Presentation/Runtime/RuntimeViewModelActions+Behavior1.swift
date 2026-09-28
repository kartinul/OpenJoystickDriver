import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// The button labels of the connected controller `selector` names; standard when unknown.
  func buttonLabels(for selector: RuntimeDeviceSelector) -> ControllerButtonLabels {
    guard case .available(let status) = statusState,
      let device = status.devices.first(where: { device in
        device.vendorID == selector.vendorID && device.productID == selector.productID
          && (selector.runtimeIdentifier == nil
            || selector.runtimeIdentifier == device.runtimeIdentifier)
      })
    else { return .standard }
    return ControllerButtonLabels(protocolID: device.protocolBinding.protocolID)
  }

  func listenForInput(for selector: RuntimeDeviceSelector) async {
    inputGeneration += 1
    let generation = inputGeneration
    inputCaptureState = .listening(selector)
    var baselineState: ControllerState?

    for attempt in 0..<50 {
      guard generation == inputGeneration else { return }
      do {
        if let state = try await gateway.controllerState(for: selector) {
          guard generation == inputGeneration else { return }
          if let baselineState,
            let detectedSource = RuntimePresentation.detectedTransition(
              from: baselineState,
              to: state,
              labels: buttonLabels(for: selector)
            )
          {
            inputCaptureState = .detected(selector, state, detectedSource)
            return
          }
          baselineState = state
        }
        if attempt < 49 { try await Task.sleep(nanoseconds: 100_000_000) }
      } catch is CancellationError {
        guard generation == inputGeneration else { return }
        inputCaptureState = .idle
        return
      } catch {
        guard generation == inputGeneration else { return }
        let message = RuntimePresentation.userFacingError(error)
        inputCaptureState =
          RuntimePresentation.isUnavailable(error)
          ? .unavailable(selector, message) : .error(selector, message)
        lastError = message
        return
      }
    }

    guard generation == inputGeneration else { return }
    inputCaptureState = .unavailable(
      selector,
      OJDLocalized.string(
        "error.noDetectedControl",
        fallback: "No new controller control was detected."
      )
    )
  }

  func cancelInputCapture() {
    inputGeneration += 1
    inputCaptureState = .idle
  }

  @discardableResult


  func createRemappingProfile(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await gateway.createRemappingProfile(profile)

    }
  }

  @discardableResult
  func updateRemappingProfile(
    _ profile: RemappingProfile,

    expectedCurrent: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: profile.id) {

      try await gateway.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
    }
  }

  @discardableResult
  func importRemappingProfile(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await gateway.importRemappingProfile(profile)
    }
  }

  @discardableResult
  func deleteRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: id) {
      try await gateway.deleteRemappingProfile(id: id)
    }
  }

  func deleteDamagedRemappingProfile(issueID: UUID) async -> String? {
    await performProfileRecovery {
      try await self.gateway.deleteDamagedRemappingProfile(issueID: issueID)
    }
  }

  func resetRemappingProfileLibrary(issueID: UUID) async -> String? {
    await performProfileRecovery {
      try await self.gateway.resetRemappingProfileLibrary(issueID: issueID)
    }
  }

  @discardableResult
  func activateRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: id) {
      try await gateway.activateRemappingProfile(id: id)
    }
  }

  @discardableResult
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await gateway.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
    }
  }

  func pairRemappingJoyCons(left: String, right: String, profileID: UUID) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "error.operationInProgress",
        fallback: "Another profile operation is already in progress."
      )
    }
    do {
      remappingState = .available(
        try await gateway.pairRemappingJoyCons(left: left, right: right, profileID: profileID)
      )
      return nil
    } catch {
      let message = RuntimePresentation.userFacingError(error)
      lastError = message
      return message
    }
  }

  func unpairRemappingJoyCons(sessionID: UUID) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "error.operationInProgress",
        fallback: "Another profile operation is already in progress."
      )
    }
    do {
      remappingState = .available(try await gateway.unpairRemappingJoyCons(sessionID: sessionID))
      return nil
    } catch {
      let message = RuntimePresentation.userFacingError(error)
      lastError = message
      return message
    }
  }

  @discardableResult
  func deactivateRemappingProfile(
    profileID: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: profileID) {
      try await gateway.deactivateRemappingProfile(profileID: profileID)
    }
  }

  /// Stores `profile` as the virtual HID profile override of `device`'s model, or clears the
  /// override when `profile` is nil so the controller selects automatically.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID?,
    for device: ApplicationServiceDeviceDescription
  ) async {
    // The service retargets every controller of the model, so the request and its failure
    // belong to the model rather than to one controller.
    let model = RuntimeControllerModel(device)
    guard virtualHIDProfileOverrideStates[model]?.inFlight != true else { return }
    virtualHIDProfileOverrideStates[model] = RuntimeVirtualHIDProfileOverrideState(
      request: profile.map { .set($0) } ?? .reset
    )
    let selector = RuntimeDeviceSelector(device: device)
    var failure: String?
    do {
      let result: VirtualHIDProfileOverrideResult
      if let profile {
        result = try await gateway.setVirtualHIDProfileOverride(profile, for: selector)
      } else {
        result = try await gateway.resetVirtualHIDProfileOverride(for: selector)
      }
      failure = result.failure.map(RuntimePresentation.virtualHIDProfileOverrideFailure)
    } catch { failure = RuntimePresentation.userFacingError(error) }
    // Keep the request in flight until the refreshed status carries the model's new profile.
    await refreshControllerInventory()
    virtualHIDProfileOverrideStates[model] = failure.map {
      RuntimeVirtualHIDProfileOverrideState(failure: $0)
    }
  }

  func suspendController(_ device: ApplicationServiceDeviceDescription) async {
    do {
      let result = try await gateway.suspendController(RuntimeDeviceSelector(device: device))
      guard result.succeeded || result.failure == .alreadySuspended else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      await refreshControllerInventory()
    } catch { lastError = RuntimePresentation.userFacingError(error) }
  }

  func resumeController(_ device: ApplicationServiceDeviceDescription) async {
    do {
      let result = try await gateway.resumeController(RuntimeDeviceSelector(device: device))
      guard result.succeeded || result.failure == .alreadyActive else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      await refreshControllerInventory()
    } catch { lastError = RuntimePresentation.userFacingError(error) }
  }

  func disconnectWirelessController(_ device: ApplicationServiceDeviceDescription) async {
    do {
      let result = try await gateway.disconnectWirelessController(
        RuntimeDeviceSelector(device: device)
      )
      guard result.succeeded else {
        let stage = result.failedStage?.rawValue ?? "disconnect-wireless-controller"
        let cause = result.detail ?? result.failure?.rawValue ?? "unknown failure"
        let code = result.systemCode.map { " (system code \($0))" } ?? ""
        let recovery = result.recovery.map { " \($0)" } ?? ""
        lastError =
          "Bluetooth disconnect failed for \(device.name) during \(stage): "
          + "\(cause)\(code).\(recovery)"
        await refreshControllerInventory()
        return
      }
      await refreshControllerInventory()
    } catch {
      lastError = RuntimePresentation.userFacingError(error)
      await refreshControllerInventory()
    }
  }

  private func locallyValid(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) -> RuntimeMutationResult? {
    do {
      try profile.validate()
      return nil
    } catch {
      lastMutationID = request.id
      lastMutationOperation = request.operation
      let message = RuntimePresentation.userFacingError(error)
      mutationState = .error(message)
      lastError = message
      return .failed(id: request.id, operation: request.operation, message: message)
    }
  }
}
