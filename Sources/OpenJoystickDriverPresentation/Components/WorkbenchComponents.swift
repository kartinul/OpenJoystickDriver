#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  // SF Symbol via NSImage(systemSymbolName:), else fallback text. Pass a nil fallback for a
  // decorative glyph whose meaning is already printed beside it: macOS 10.15 has no SF Symbols,
  // and fallback text in a glyph-sized frame wraps into a column.
  struct OJDSystemSymbol: View {
    let name: String
    let fallback: String?
    let fallbackSymbolName: String?

    init(name: String, fallback: String?, fallbackSymbolName: String? = nil) {
      self.name = name
      self.fallback = fallback
      self.fallbackSymbolName = fallbackSymbolName
    }

    var body: some View {
      if #available(macOS 11.0, *) {
        let preferredImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let fallbackImage = fallbackSymbolName.flatMap {
          NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        }
        switch SystemSymbolPolicy.resolution(
          preferred: name,
          fallback: fallbackSymbolName,
          preferredIsAvailable: preferredImage != nil,
          fallbackIsAvailable: fallbackImage != nil
        ) {
        case .symbol(let resolvedName):
          if resolvedName == name, let preferredImage {
            Image(nsImage: preferredImage)
          } else if let fallbackImage {
            Image(nsImage: fallbackImage)
          }
        case .text: if let fallback { Text(fallback).font(.caption) }
        }
      } else if let fallback {
        Text(fallback).font(.caption)
      }
    }
  }

  struct OJDListGlyphSlot<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
      content.font(.system(size: 15, weight: .medium)).frame(
        width: 28,
        height: 28,
        alignment: .center
      ).ojdAccessibilityHidden(true)
    }
  }

  struct OJDCompactSymbolButton: View {
    let symbolName: String
    let fallbackSymbolName: String?
    let label: String
    let action: () -> Void

    init(
      symbolName: String,
      fallbackSymbolName: String? = nil,
      label: String,
      action: @escaping () -> Void
    ) {
      self.symbolName = symbolName
      self.fallbackSymbolName = fallbackSymbolName
      self.label = label
      self.action = action
    }

    var body: some View {
      Button(action: action) {
        OJDSystemSymbol(name: symbolName, fallback: label, fallbackSymbolName: fallbackSymbolName)
          .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
      }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(label).ojdHelp(label)
    }
  }

  extension View {
    @ViewBuilder
    func ojdPrimaryAction() -> some View {
      if #available(macOS 11.0, *) { keyboardShortcut(.defaultAction) } else { self }
    }

    @ViewBuilder
    func ojdAccessibilityLabel(_ label: String) -> some View {
      if #available(macOS 11.0, *) {
        accessibilityLabel(Text(label))
      } else {
        accessibility(label: Text(label))
      }
    }

    @ViewBuilder
    func ojdAccessibilityValue(_ value: String) -> some View {
      if #available(macOS 11.0, *) {
        accessibilityValue(Text(value))
      } else {
        accessibility(value: Text(value))
      }
    }

    @ViewBuilder
    func ojdAccessibilityHidden(_ hidden: Bool) -> some View {
      if #available(macOS 11.0, *) {
        accessibilityHidden(hidden)
      } else {
        accessibility(hidden: hidden)
      }
    }

    @ViewBuilder
    func ojdAccessibilitySelection(_ selected: Bool) -> some View {
      let value = OJDLocalized.string(
        selected ? "common.selected" : "common.notSelected",
        fallback: selected ? "Selected" : "Not selected"
      )
      if #available(macOS 11.0, *) {
        accessibilityValue(Text(value)).accessibilityAddTraits(selected ? .isSelected : [])
      } else {
        accessibility(value: Text(value)).accessibility(addTraits: selected ? .isSelected : [])
      }
    }
  }

  struct SettingsSidebar: View {
    @ObservedObject
    var navigation: SettingsNavigationModel
    let panes: [SettingsPane]

    var body: some View {
      List(selection: selection) {
        ForEach(panes) { pane in
          HStack(spacing: 8) {
            OJDSystemSymbol(name: pane.symbolName, fallback: nil).frame(width: 18)
              .ojdAccessibilityHidden(true)
            Text(pane.title)
            Spacer(minLength: 0)
          }.padding(.vertical, 3).tag(pane)
        }
      }.listStyle(SidebarListStyle()).frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
        .ojdAccessibilityLabel(
          OJDLocalized.string("settings.navigation", fallback: "Settings navigation")
        )
    }

    private var selection: Binding<SettingsPane?> {
      Binding(
        get: { navigation.selectedPane },
        set: { pane in if let pane { navigation.requestPane(pane) } }
      )
    }
  }

#endif
