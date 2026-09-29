import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct SettingsNavigationTests {
  @Test
  @MainActor
  func dockVisibilityTracksPrimaryWindowsAndRetriesFailedPolicyChanges() {
    var requestedPolicies: [NSApplication.ActivationPolicy] = []
    var shouldSucceed = true
    let visibility = PrimaryWindowVisibilityController { policy in
      requestedPolicies.append(policy)
      return shouldSucceed
    }

    #expect(visibility.appliedPolicy == .accessory)
    visibility.opened(.workbench)
    #expect(requestedPolicies == [.regular])
    #expect(visibility.appliedPolicy == .regular)

    visibility.opened(.inputTest)
    visibility.closed(.workbench)
    #expect(requestedPolicies == [.regular])
    #expect(visibility.isOpen(.inputTest))

    shouldSucceed = false
    visibility.closed(.inputTest)
    #expect(requestedPolicies == [.regular, .accessory])
    #expect(visibility.appliedPolicy == .regular)

    shouldSucceed = true
    visibility.opened(.inputTest)
    visibility.closed(.inputTest)
    #expect(requestedPolicies == [.regular, .accessory, .accessory])
    #expect(visibility.appliedPolicy == .accessory)
  }

  @Test
  func settingsWindowUsesStableContentSizingAcrossPanes() {
    #expect(SettingsWindowSizingPolicy.defaultContentSize == NSSize(width: 1_040, height: 700))
    #expect(SettingsWindowSizingPolicy.minimumContentSize == NSSize(width: 800, height: 560))
    #expect(
      SettingsWindowSizingPolicy.fittingContentSize(NSSize(width: 1_100, height: 700))
        == NSSize(width: 1_100, height: 700)
    )
    #expect(
      SettingsWindowSizingPolicy.fittingContentSize(NSSize(width: 600, height: 400))
        == SettingsWindowSizingPolicy.minimumContentSize
    )
  }

  @Test
  func restoredAndLiveResizeFramesCannotCrossTheContentMinimum() {
    let minimum = NSSize(width: 816, height: 604)
    let restored = WindowFramePolicy.fittingFrame(
      NSRect(x: 200, y: 300, width: 640, height: 420),
      minimumSize: minimum
    )
    #expect(restored == NSRect(x: 200, y: 116, width: 816, height: 604))
    #expect(
      WindowFramePolicy.fittingSize(NSSize(width: 700, height: 500), minimumSize: minimum)
        == minimum
    )
    #expect(
      WindowFramePolicy.fittingSize(NSSize(width: 1_100, height: 760), minimumSize: minimum)
        == NSSize(width: 1_100, height: 760)
    )
  }

  @Test
  @MainActor
  func frameMinimumConvertsBackToTheRequiredContentMinimum() {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: SettingsWindowSizingPolicy.defaultContentSize),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.toolbar = NSToolbar(identifier: "SizingPolicyTest")
    let minimumFrameSize = SettingsWindowSizingPolicy.minimumFrameSize(for: window)
    let convertedContentSize = window.contentRect(
      forFrameRect: NSRect(origin: .zero, size: minimumFrameSize)
    ).size

    #expect(convertedContentSize == SettingsWindowSizingPolicy.minimumContentSize)
  }

  @Test
  func restoredWindowFramesAreClampedToTheUsableScreen() {
    let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    #expect(
      WindowFramePolicy.clampedFrame(NSRect(x: 1_300, y: -100, width: 900, height: 620), to: screen)
        == NSRect(x: 540, y: 0, width: 900, height: 620)
    )
    #expect(
      WindowFramePolicy.clampedFrame(
        NSRect(x: 1_300, y: 700, width: 500, height: 300),
        to: screen,
        minimumSize: NSSize(width: 816, height: 604)
      ) == NSRect(x: 624, y: 296, width: 816, height: 604)
    )
  }

  @Test
  func developerPaneIsProgressivelyDisclosed() {
    #expect(
      SettingsPane.primaryCases(developerToolsEnabled: false) == [
        .overview, .controllers, .profiles, .console, .settings,
      ]
    )
    #expect(
      SettingsPane.primaryCases(developerToolsEnabled: true) == [
        .overview, .controllers, .profiles, .console, .developer, .settings,
      ]
    )
  }

  @Test
  @MainActor
  func disablingDeveloperToolsLeavesTheHiddenPane() {
    let navigation = SettingsNavigationModel(developerToolsEnabled: true)
    navigation.requestPane(.developer)
    #expect(navigation.selectedPane == .developer)

    navigation.setDeveloperToolsEnabled(false)

    #expect(navigation.selectedPane == .settings)
  }

  @Test
  @MainActor
  func restoresTheLastAcceptedPane() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let initial = SettingsNavigationModel(persistence: persistence)
    #expect(initial.selectedPane == .overview)
    initial.requestPane(.profiles)
    #expect(initial.selectedPane == .profiles)

    let restored = SettingsNavigationModel(persistence: persistence)
    #expect(restored.selectedPane == .profiles)
  }

  @Test
  @MainActor
  func dirtySelectionPersistsOnlyAfterDiscard() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let navigation = SettingsNavigationModel(persistence: persistence)
    navigation.requestPane(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestPane(.settings)

    #expect(navigation.selectedPane == .controllers)
    #expect(navigation.pendingPane == .settings)
    #expect(navigation.isDiscardConfirmationPresented)
    let beforeDiscard = SettingsNavigationModel(persistence: persistence)
    #expect(beforeDiscard.selectedPane == .controllers)

    navigation.discardPendingPane()
    #expect(navigation.selectedPane == .settings)
    #expect(navigation.pendingPane == nil)
    #expect(!navigation.isDiscardConfirmationPresented)
    let afterDiscard = SettingsNavigationModel(persistence: persistence)
    #expect(afterDiscard.selectedPane == .settings)
  }

  @Test
  @MainActor
  func canceledDirtySelectionLeavesThePersistedPaneUnchanged() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let navigation = SettingsNavigationModel(persistence: persistence)
    navigation.requestPane(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestPane(.console)
    navigation.cancelPendingPane()

    #expect(navigation.selectedPane == .controllers)
    #expect(navigation.pendingPane == nil)
    let restored = SettingsNavigationModel(persistence: persistence)
    #expect(restored.selectedPane == .controllers)
  }

  @Test
  @MainActor
  func activeProfileMutationKeepsTheProfilesPaneMountedUntilResolution() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let navigation = SettingsNavigationModel(persistence: persistence)
    let request = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    navigation.requestPane(.profiles)
    navigation.setProfilesEditorDirty(true)
    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(false)

    navigation.requestPane(.settings)

    #expect(navigation.selectedPane == .profiles)
    #expect(navigation.pendingPane == nil)
    #expect(!navigation.isDiscardConfirmationPresented)

    #expect(navigation.finishProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(true)
    navigation.requestPane(.settings)

    #expect(navigation.pendingPane == .settings)
    #expect(navigation.isDiscardConfirmationPresented)

    navigation.cancelPendingPane()
    navigation.setProfilesEditorDirty(false)
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .settings)
  }

  @Test
  @MainActor
  func overlappingProfileMutationCannotReleaseTheFirstNavigationOwner() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = SettingsNavigationModel(
      persistence: UserDefaultsSettingsPanePersistence(defaults: defaults)
    )
    let first = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    let second = RuntimeMutationRequest(operation: .importProfile(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(second))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == nil)

    #expect(!navigation.finishProfilesEditorMutation(second))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == nil)

    #expect(navigation.finishProfilesEditorMutation(first))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .settings)
  }

  @Test
  @MainActor
  func matchingPreflightFailureReleasesNavigationOwner() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = SettingsNavigationModel(
      persistence: UserDefaultsSettingsPanePersistence(defaults: defaults)
    )
    let request = RuntimeMutationRequest(operation: .update(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == nil)

    #expect(
      !navigation.finishProfilesEditorMutation(RuntimeMutationRequest(operation: request.operation))
    )
    #expect(navigation.ownsProfilesEditorMutation(request))
    #expect(navigation.finishProfilesEditorMutation(request))

    navigation.setProfilesEditorDirty(false)
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .settings)
  }

  @Test
  @MainActor
  func preflightFailureReleasesBothOwnersAndPreservesDirtyDraft() async {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let original = makeProfile(name: "Original")
    let invalid = makeProfile(id: original.id, name: "")
    let request = RuntimeMutationRequest(operation: .update(profileID: original.id))
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let library = ProfileLibraryModel(runtime: RuntimeViewModel(gateway: gateway))
    var transition = ProfileEditorTransitionState()
    let navigation = SettingsNavigationModel(
      persistence: UserDefaultsSettingsPanePersistence(defaults: defaults)
    )

    transition.setDirty(true)
    #expect(transition.beginMutation(request) == .acquired)
    #expect(navigation.beginProfilesEditorMutation(request))

    let result = await library.updateRemappingProfile(
      invalid,
      expectedCurrent: original,
      request: request
    )
    #expect(result.request == request)
    #expect(transition.finishMutationIfOwned(result.request, succeeded: false).didRelease)
    #expect(navigation.finishProfilesEditorMutation(result.request))
    navigation.setProfilesEditorDirty(transition.isDirty)

    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == .settings)
    #expect(navigation.isDiscardConfirmationPresented)
    #expect(transition.isDirty)
  }
}
