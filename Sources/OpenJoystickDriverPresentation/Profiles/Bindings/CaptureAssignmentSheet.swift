#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  struct CaptureAssignmentSheet: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let capabilities: ControllerProfileCapabilities
    let onAdd: (RemappingSource, RemappingDestination) -> Void
    @Environment(\.presentationMode)
    var presentationMode
    @State
    var source: RemappingSource = .button(.south)
    @State
    var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])
    @State
    var keyboardDestinationCleared = false
    @State
    var keyboardCaptureActive = false
    @State
    var selectedRuntimeIdentifier: String?
  }

#endif
