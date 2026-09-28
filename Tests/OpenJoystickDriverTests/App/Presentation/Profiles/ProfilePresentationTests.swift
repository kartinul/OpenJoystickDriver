import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfilePresentationTests {
  @Test
  func focusedEditorContainsEverySectionInTaskOrder() {
    #expect(
      ProfilePresentationPolicy.sectionOrder == [.assignments, .combinations, .layers, .controller]
    )
    #expect(ProfilePresentationPolicy.defaultSection == .assignments)
  }

  @Test
  func sectionNavigationUsesAvailableEditorWidth() {
    #expect(ProfilePresentationPolicy.navigationStyle(for: 619) == .popUp)
    #expect(ProfilePresentationPolicy.navigationStyle(for: 620) == .segmented)
  }

  @Test
  func assignmentRowsStackOnlyBelowTheirReadableWidth() {
    #expect(ProfilePresentationPolicy.assignmentRowLayout(for: 679) == .stacked)
    #expect(ProfilePresentationPolicy.assignmentRowLayout(for: 680) == .inline)
  }

  @Test
  func optionalEditorsGrowOnlyWhenTheirFeatureIsEnabled() {
    #expect(
      ProfilePresentationPolicy.optionalEditorHeight(enabled: false, compact: 260, expanded: 600)
        == 260
    )
    #expect(
      ProfilePresentationPolicy.optionalEditorHeight(enabled: true, compact: 260, expanded: 600)
        == 600
    )
  }

  @Test
  func listAndDetailLayoutPreservesBothMinimumWidths() {
    #expect(WorkspaceListDetailPolicy.layout(for: 800) == .stacked)
    #expect(WorkspaceListDetailPolicy.layout(for: 801) == .sideBySide)
    #expect(WorkspaceListDetailPolicy.listWidth(for: 801) == 200)
    #expect(WorkspaceListDetailPolicy.listWidth(for: 821) == 220)
    #expect(WorkspaceListDetailPolicy.listWidth(for: 1_000) == 240)
    #expect(WorkspaceListDetailPolicy.compactListHeight(itemCount: 1, availableHeight: 560) == 96)
    #expect(
      WorkspaceListDetailPolicy.compactListHeight(itemCount: 20, availableHeight: 560) == 190.4
    )
    #expect(WorkspaceListDetailPolicy.compactListHeight(itemCount: 20, availableHeight: 800) == 200)
  }

  @Test
  func controllerDetailsChangeColumnsOnlyAtDocumentedBoundaries() {
    #expect(ControllerDetailLayoutPolicy.factColumnCount(for: 559) == 1)
    #expect(ControllerDetailLayoutPolicy.factColumnCount(for: 560) == 2)
  }

  @Test
  @MainActor
  func librarySelectionRemainsStableUntilItsSelectedItemDisappears() {
    let profile = makeProfile(name: "Healthy")
    let damaged = ApplicationServiceRemappingProfileIssue(
      id: UUID(),
      kind: .damagedProfile,
      message: "damaged"
    )
    let unusable = ApplicationServiceRemappingProfileIssue(
      id: UUID(),
      kind: .unusableLibrary,
      message: "unusable"
    )
    let model = ProfilesViewModel()
    let partial = ApplicationServiceRemappingSnapshotPayload(
      profiles: [profile],
      activeProfiles: [],
      routes: [],
      profileIssues: [damaged],
      postEventAccess: .granted
    )

    model.reconcileSelection(with: partial)
    #expect(model.selectedProfileID == profile.id)
    model.selectedRecoveryIssueID = damaged.id
    model.reconcileSelection(with: partial)
    #expect(model.selectedRecoveryIssueID == damaged.id)

    let unrecoverable = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      profileIssues: [unusable],
      postEventAccess: .granted
    )
    model.reconcileSelection(with: unrecoverable)
    #expect(model.selectedRecoveryIssueID == unusable.id)
    #expect(model.selectedProfileID == nil)
  }
}
