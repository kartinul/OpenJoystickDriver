#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  struct ControllerDetailView: View {
    let device: ApplicationServiceDeviceDescription
    let activeProfile: RuntimeActiveProfileState
    let retry: () -> Void
    @ObservedObject
    var viewModel: RuntimeViewModel
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
    @State
    var confirmsWirelessDisconnect = false
  }

  struct ControllerFactView: View {
    let label: String
    let value: String

    var body: some View {
      VStack(alignment: .leading, spacing: 3) {
        Text(label).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Text(value).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

#endif
