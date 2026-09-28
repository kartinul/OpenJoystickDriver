import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Build identity")
struct BuildIdentityTests {
  @Test
  func JSONUsesTypedLowerCamelFields() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: String(repeating: "a", count: 40),
      sourceState: .clean
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(identity)) as? [String: Any]
    )

    #expect(object["semanticVersion"] as? String == "0.5.0-beta.4")
    #expect(object["appBundleVersion"] as? String == "1.4.89")
    #expect(object["sourceState"] as? String == "clean")
  }

  @Test
  func displayCarriesProvenanceAsSemVerBuildMetadata() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: "0123456789abcdef0123456789abcdef01234567",
      sourceState: .dirty
    )

    #expect(identity.display == "0.5.0-beta.4+build.1.4.89.sha.0123456789ab.dirty")
    let parsed = try #require(SemanticVersion(identity.display))
    #expect(parsed == SemanticVersion("0.5.0-beta.4"))
  }

  @Test
  func statusJSONExposesBuildIdentityAtTheTopLevel() throws {
    let identity = BuildIdentity(
      semanticVersion: "0.5.0-beta.4",
      appBundleVersion: "1.4.89",
      sourceCommit: String(repeating: "b", count: 40),
      sourceState: .clean
    )
    let status = ApplicationServiceStatusPayload(
      buildIdentity: identity,
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: []
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any]
    )

    let encodedIdentity = try #require(object["buildIdentity"] as? [String: Any])
    #expect(encodedIdentity["sourceCommit"] as? String == identity.sourceCommit)
  }
}
