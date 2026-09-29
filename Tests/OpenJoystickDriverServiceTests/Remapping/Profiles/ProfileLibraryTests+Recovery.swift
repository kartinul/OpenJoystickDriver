import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  @Test
  func profileWithRemovedGyroFieldIsRecoveredAsDamaged() async throws {
    try await withLibrary { library, url in
      let valid = makeProfile(name: "Valid")
      let legacy = makeProfile(name: "Legacy")
      let validObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
      )
      var legacyObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
      )
      legacyObject["gyroOutput"] = ["mode": "mouse", "virtualMotion": true]
      try JSONSerialization.data(withJSONObject: [
        "profiles": [validObject, legacyObject], "activeProfiles": [],
      ]).write(to: url)

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
    }
  }
}
