import Foundation
import OpenJoystickDriverKit

/// Stable failures from the locally persisted remapping-profile library.
enum RemappingProfileLibraryError: Error, Equatable, LocalizedError, Sendable {
  case corruptLibrary
  case duplicateName(String)
  case invalidProfile(RemappingValidationError)
  case librarySizeExceeded(Int)
  case profileCountExceeded(Int)
  case profileAlreadyExists(UUID)
  case profileNotFound(UUID)
  case pairProfileRequiresExplicitSession
  case profileUpdateConflict(UUID)
  case unreadableLibrary
  case unwritableLibrary
  case profileRecoveryRequired
  case profileIssueNotFound(UUID)

  var errorDescription: String? {
    switch self {
    case .corruptLibrary: "The remapping profile library is corrupt."
    case .duplicateName(let name): "A remapping profile named \(name) already exists."
    case .invalidProfile(let error): error.localizedDescription
    case .librarySizeExceeded(let size):
      "The remapping profile library is too large (\(size) bytes)."
    case .profileCountExceeded(let count):
      "The remapping profile library cannot contain \(count) profiles."
    case .profileAlreadyExists(let id): "The remapping profile \(id.uuidString) already exists."
    case .profileNotFound(let id): "The remapping profile \(id.uuidString) does not exist."
    case .pairProfileRequiresExplicitSession:
      "Paired Joy-Con profiles are started with an explicit pair session."
    case .profileUpdateConflict(let id):
      "The remapping profile \(id.uuidString) changed since it was read."
    case .unreadableLibrary: "The remapping profile library could not be read."
    case .unwritableLibrary: "The remapping profile library could not be written."
    case .profileRecoveryRequired: "Damaged profiles must be repaired before changing the library."
    case .profileIssueNotFound: "The selected damaged profile is no longer current."
    }
  }
}

/// The single application-service writer for locally authored remapping profiles.
actor RemappingProfileLibrary {
  static let maximumProfileCount = RemappingPayloadLimits.maximumProfileCount
  static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes

  let fileURL: URL
  var library: RemappingProfileLibraryState?

  var profileIssues: [UUID: RecoveryIssue] = [:]
  var originalRecoveryData: Data?

  init(fileURL: URL = RemappingProfileLibrary.defaultFileURL) { self.fileURL = fileURL }
}
