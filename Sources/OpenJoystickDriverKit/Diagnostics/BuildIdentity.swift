import Foundation

public struct BuildIdentity: Codable, Equatable, Sendable {
  public enum SourceState: String, Codable, Sendable {
    case clean
    case dirty
    case unknown
  }

  public let semanticVersion: String
  public let appBundleVersion: String
  public let sourceCommit: String
  public let sourceState: SourceState

  public init(
    semanticVersion: String,
    appBundleVersion: String,
    sourceCommit: String,
    sourceState: SourceState
  ) {
    self.semanticVersion = semanticVersion
    self.appBundleVersion = appBundleVersion
    self.sourceCommit = sourceCommit
    self.sourceState = sourceState
  }

  public static func current(bundle: Bundle = .main) -> Self {
    let info = bundle.infoDictionary ?? [:]
    return Self(
      semanticVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
      appBundleVersion: info["CFBundleVersion"] as? String ?? "unknown",
      sourceCommit: info["OJDSourceCommit"] as? String ?? "unknown",
      sourceState: (info["OJDSourceState"] as? String).flatMap(SourceState.init) ?? .unknown
    )
  }

  /// The release version with SemVer build metadata for provenance, such as
  /// `0.5.0+build.1.4.89.sha.0123456789ab.dirty`. Metadata never orders versions.
  public var display: String {
    let shortCommit = sourceCommit.count == 40 ? String(sourceCommit.prefix(12)) : sourceCommit
    var metadata = ["build", appBundleVersion, "sha", shortCommit]
    if sourceState == .dirty { metadata.append("dirty") }
    return "\(semanticVersion)+\(metadata.joined(separator: "."))"
  }

  private enum CodingKeys: String, CodingKey {
    case semanticVersion
    case appBundleVersion
    case sourceCommit
    case sourceState
  }
}
