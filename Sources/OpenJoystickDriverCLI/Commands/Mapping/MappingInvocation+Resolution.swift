import Foundation
import OpenJoystickDriverKit

extension MappingInvocation {
  internal func deleteByID(
    client: any MappingServiceClient,
    remove: (RemappingProfile, UUID) throws -> RemappingProfile
  ) async throws -> String {
    let (selector, opts) = try selectorArguments()
    let options = try MappingOptions(opts)
    try options.validate(allowed: ["--id"])
    let profile = try await resolve(selector, client: client)
    let id = try MappingSyntax.uuid(try options.required("--id"), option: "--id")
    let updated = try remove(profile, id)
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  internal func resolve(
    _ selector: String,
    client: any MappingServiceClient
  ) async throws -> RemappingProfile {
    if let id = UUID(uuidString: selector) { return try await client.profile(id: id) }
    let matches = try await client.snapshot().profiles.filter {
      $0.name.caseInsensitiveCompare(selector) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw MappingCommandError.profileNotFound(
        CLILocalized.format("cli.mapping.profile_missing", "No profile named '%@'.", selector)
      )
    }
    guard matches.count == 1, let profile = matches.first else {
      throw MappingCommandError.ambiguousProfile(
        CLILocalized.format(
          "cli.mapping.profile_ambiguous",
          "Profile name '%@' is ambiguous.",
          selector
        )
      )
    }
    return profile
  }

  internal var profileArguments: ArraySlice<String> {
    ["chord", "sequence", "layer"].contains(command) ? arguments.dropFirst() : arguments[...]
  }

  internal func selectorArguments() throws -> (String, [String]) {
    guard let selector = profileArguments.first, !selector.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.profile_required", "A profile UUID or name is required.")
      )
    }
    return (selector, Array(profileArguments.dropFirst()))
  }

  internal func soleArgument(_ usage: String) throws -> String {
    guard profileArguments.count == 1, let value = profileArguments.first else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.usage_prefix", "Usage: %@", usage)
      )
    }
    return value
  }

  internal func render(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    profileID: UUID
  ) -> String {
    guard let profile = snapshot.profiles.first(where: { $0.id == profileID }) else {
      return MappingRenderer.snapshot(snapshot)
    }
    return MappingRenderer.profile(profile)
  }
}
