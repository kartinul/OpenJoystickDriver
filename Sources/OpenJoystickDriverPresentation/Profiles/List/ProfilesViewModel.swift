#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit

  actor ProfileDocumentService {
    func load(from url: URL) throws -> RemappingProfile {
      try RemappingProfileFileStore.load(from: url)
    }

    func write(_ profile: RemappingProfile, to url: URL) throws {
      try RemappingProfileFileStore.write(profile, to: url)
    }
  }

  @MainActor
  final class ProfilesViewModel: ObservableObject {
    let documents: ProfileDocumentService
    let capabilityRegistry = ProtocolDriverRegistry()
    @Published
    var selectedProfileID: UUID?
    @Published
    var selectedRecoveryIssueID: UUID?
    @Published
    var isCreatingProfile = false
    @Published
    var activeAlert: ProfilesAlert?
    @Published
    var profileActionError: String?
    @Published
    var pairingProfile: RemappingProfile?
    @Published
    var selectedEditorSection = ProfilePresentationPolicy.defaultSection

    var editorTransition = ProfileEditorTransitionState()
    var observedDiscardGeneration = 0
    var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload?
    var preservedEditorProfile: RemappingProfile?
    var editorGeneration = 0
    private var editorViewModel: ProfileEditorViewModel?
    private var editorViewModelGeneration: (discard: Int, refresh: Int)?

    init(documents: ProfileDocumentService = ProfileDocumentService()) {
      self.documents = documents
    }

    func editor(for profile: RemappingProfile, discardGeneration: Int) -> ProfileEditorViewModel {
      let generation = (discard: discardGeneration, refresh: editorGeneration)
      if let editorViewModel, editorViewModel.expectedCurrent.id == profile.id,
        editorViewModelGeneration?.discard == generation.discard,
        editorViewModelGeneration?.refresh == generation.refresh
      {
        return editorViewModel
      }
      let editor = ProfileEditorViewModel(profile: profile)
      editorViewModel = editor
      editorViewModelGeneration = generation
      return editor
    }

    func resetEditor() {
      editorViewModel = nil
      editorViewModelGeneration = nil
    }

    func reconcileSelection(with snapshot: ApplicationServiceRemappingSnapshotPayload) {
      if let selectedRecoveryIssueID,
        !snapshot.profileIssues.contains(where: { $0.id == selectedRecoveryIssueID })
      {
        self.selectedRecoveryIssueID = nil
      }
      if let selectedProfileID, !snapshot.profiles.contains(where: { $0.id == selectedProfileID }) {
        self.selectedProfileID = snapshot.profiles.first?.id
      }
      if selectedProfileID == nil, selectedRecoveryIssueID == nil {
        selectedProfileID = snapshot.profiles.first?.id
        if selectedProfileID == nil { selectedRecoveryIssueID = snapshot.profileIssues.first?.id }
      }
    }
  }

  @MainActor
  final class ProfileEditorViewModel: ObservableObject {
    @Published
    var draft: RuntimeProfileDraft
    @Published
    var activeSheet: ProfileEditorSheet?
    @Published
    var showingConflict = false
    @Published
    var localError: String?
    @Published
    var saveError: String?

    @Published
    var expectedCurrent: RemappingProfile
    @Published
    var saveState = ProfileEditorSaveState()

    init(profile: RemappingProfile) {
      draft = RuntimeProfileDraft(profile: profile)
      expectedCurrent = profile
    }
  }

#endif
