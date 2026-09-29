#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  enum InputTestSection: Int, CaseIterable, Equatable {
    case liveInput
    case axes
    case motion
    case rumble
    case lighting
  }

  enum InputTestLayoutPolicy {
    enum WidthClass: Equatable {
      case compact
      case regular
      case wide
    }

    static let sectionOrder = InputTestSection.allCases

    static func widthClass(for width: CGFloat) -> WidthClass {
      if width < 780 { return .compact }
      if width < 1_060 { return .regular }
      return .wide
    }
  }

  struct InputTestView: View {
    @ObservedObject
    var model: InputTestViewModel
    let runtimeViewModel: RuntimeViewModel
  }

  struct InputTestOutputControlsView<Content: View>: View {
    @ObservedObject
    var settings: InputTestOutputSettings
    @ViewBuilder
    let content: () -> Content

    var body: some View { content() }
  }

  struct OJDPhysicalColorWell: NSViewRepresentable {
    @Binding
    var color: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSColorWell {
      let well = NSColorWell()
      well.target = context.coordinator
      well.action = #selector(Coordinator.changed(_:))
      return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
      context.coordinator.parent = self
      well.color = color
    }

    final class Coordinator: NSObject {
      var parent: OJDPhysicalColorWell

      init(parent: OJDPhysicalColorWell) { self.parent = parent }

      @MainActor
      @objc
      func changed(_ sender: NSColorWell) { parent.color = sender.color }
    }
  }

#endif
