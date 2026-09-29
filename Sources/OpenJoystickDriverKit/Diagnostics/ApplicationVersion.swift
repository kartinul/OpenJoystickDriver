import Foundation

package enum ApplicationVersion {
  package static var current: String { buildIdentity.semanticVersion }

  package static var buildIdentity: BuildIdentity { .current() }

  package static var display: String { buildIdentity.display }
}
