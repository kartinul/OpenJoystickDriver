import Testing

@testable import OpenJoystickDriver

struct CommandCatalogTests {
  @Test
  func catalogPathsAreUnique() {
    let commands = InstalledCommandCatalog.commands
    let paths = commands.map(\.path)

    #expect(Set(paths).count == paths.count)
  }

  @Test
  func catalogUsesStableLogicalOrder() {
    let groups = InstalledCommandCatalog.commands.map(\.group)
    let order = ["Overview", "Controllers", "Configuration", "System", "Support"]

    #expect(
      groups
        == groups.sorted { left, right in
          guard let leftIndex = order.firstIndex(of: left),
            let rightIndex = order.firstIndex(of: right)
          else { return false }
          return leftIndex < rightIndex
        }
    )
    #expect(InstalledCommandCatalog.commands.first?.path == "status [--json]")
  }

  @Test
  func listsTheVirtualProfileOverrideCommandsInsteadOfCompat() throws {
    let commands = InstalledCommandCatalog.commands

    for prefix in ["controller virtual set ", "controller virtual reset "] {
      let command = try #require(commands.first { $0.path.hasPrefix(prefix) })
      #expect(command.audience == .advanced)
      #expect(command.sideEffect == .persistentConfiguration)
    }
    #expect(
      commands.first { $0.path.hasPrefix("controller virtual set ") }?.path.contains(
        "<hid-xbox-one-s-bt|hid-generic>"
      ) == true
    )
    #expect(
      commands.first { $0.path.hasPrefix("controller virtual reset ") }?.summary.contains("--all")
        == true
    )
    #expect(!commands.contains { $0.path.hasPrefix("compat") })
  }

}
