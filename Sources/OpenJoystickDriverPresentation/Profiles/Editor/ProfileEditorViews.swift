#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Profile editor

  struct ProfileEditorView: View {
    let profile: RemappingProfile
    let capabilities: ControllerProfileCapabilities
    @ObservedObject
    var editor: ProfileEditorViewModel
    @ObservedObject
    var viewModel: RuntimeViewModel
    @ObservedObject
    var library: ProfileLibraryModel
    let isActive: Bool
    let isEditingBlocked: Bool
    @Binding
    var selectedSection: ProfileEditorSection
    let onDelete: () -> Void
    let onExport: (RemappingProfile) -> Void
    let onEditingStateChanged: (Bool) -> Void
    let onMutationStarted: (RuntimeMutationRequest) -> Bool
    let onMutationResult: (RuntimeMutationResult) -> Void
    @State
    var confirmation: ProfileEditorConfirmation?

    init(
      profile: RemappingProfile,
      capabilities: ControllerProfileCapabilities,
      editor: ProfileEditorViewModel,
      viewModel: RuntimeViewModel,
      library: ProfileLibraryModel,
      isActive: Bool,
      isEditingBlocked: Bool,
      selectedSection: Binding<ProfileEditorSection>,
      onDelete: @escaping () -> Void,
      onExport: @escaping (RemappingProfile) -> Void,
      onEditingStateChanged: @escaping (Bool) -> Void,
      onMutationStarted: @escaping (RuntimeMutationRequest) -> Bool,
      onMutationResult: @escaping (RuntimeMutationResult) -> Void
    ) {
      self.profile = profile
      self.capabilities = capabilities
      self.editor = editor
      self.viewModel = viewModel
      self.library = library
      self.isActive = isActive
      self.isEditingBlocked = isEditingBlocked
      _selectedSection = selectedSection
      self.onDelete = onDelete
      self.onExport = onExport
      self.onEditingStateChanged = onEditingStateChanged
      self.onMutationStarted = onMutationStarted
      self.onMutationResult = onMutationResult
    }
  }

  enum ProfileEditorConfirmation: Identifiable {
    case activateEmpty
    case clearInputs

    var id: String {
      switch self {
      case .activateEmpty: "activate-empty"
      case .clearInputs: "clear-inputs"
      }
    }
  }

#endif
