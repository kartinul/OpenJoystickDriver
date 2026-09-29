import Foundation
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

actor MockMappingClient: MappingServiceClient {
  let snapshotValue: ApplicationServiceRemappingSnapshotPayload
  let updateError: ApplicationServiceRemappingRPCError?
  var mutationCount = 0
  private(set) var submittedProfile: RemappingProfile?
  private(set) var updateAttempts = 0
  private(set) var lastExpectedCurrent: RemappingProfile?
  private(set) var expectedProfiles: [RemappingProfile] = []
  private(set) var calibrationCalls = 0
  private(set) var calibrationCommand: RemappingMotionCalibrationCommand?
  var pairRequest: (left: String, right: String, profileID: UUID)?
  var unpairedSessionID: UUID?

  init(
    snapshotValue: ApplicationServiceRemappingSnapshotPayload,
    updateError: ApplicationServiceRemappingRPCError? = nil
  ) {
    self.snapshotValue = snapshotValue
    self.updateError = updateError
  }

  func snapshot() -> ApplicationServiceRemappingSnapshotPayload { snapshotValue }

  func profile(id: UUID) throws -> RemappingProfile {
    guard let profile = snapshotValue.profiles.first(where: { $0.id == id }) else {
      throw MappingCommandError.profileNotFound(id.uuidString)
    }
    return profile
  }

  func create(_ profile: RemappingProfile) -> ApplicationServiceRemappingSnapshotPayload {
    submittedProfile = profile
    mutationCount += 1
    return snapshotValue
  }

  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) throws -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    submittedProfile = profile
    updateAttempts += 1
    lastExpectedCurrent = expectedCurrent
    expectedProfiles.append(expectedCurrent)
    if let updateError { throw updateError }
    return snapshotValue
  }

  func importProfile(_ profile: RemappingProfile) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }

  func delete(id: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }

  func activate(id: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }

  func deactivate(vendorID: UInt16, productID: UInt16) -> ApplicationServiceRemappingSnapshotPayload
  {
    mutationCount += 1
    return snapshotValue
  }

  func deactivate(profileID: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }

  func access(request: Bool) -> RemappingPostEventAccessState { .granted }

  func motionCalibration(
    runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand?
  ) throws -> RemappingMotionCalibrationStatus {
    calibrationCalls += 1
    calibrationCommand = command
    throw ApplicationServiceRemappingRPCError(
      code: .controllerUnavailable,
      message: runtimeIdentifier
    )
  }
}
