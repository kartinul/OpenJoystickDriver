import Foundation

/// A profile edit referenced an item that the profile does not contain.
///
/// Editors map these cases to their own user-visible messages.
package enum RemappingProfileEditingError: Error, Equatable, Sendable {
  case chordNotFound(UUID)
  case layerNotFound(UUID)
  case sequenceNotFound(UUID)
}
