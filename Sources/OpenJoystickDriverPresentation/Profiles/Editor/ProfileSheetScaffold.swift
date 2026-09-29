#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  struct ProfileSheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let help: String?
    let error: String?
    private let content: Content
    private let footer: Footer

    init(
      title: String,
      help: String? = nil,
      error: String? = nil,
      @ViewBuilder content: () -> Content,
      @ViewBuilder footer: () -> Footer
    ) {
      self.title = title
      self.help = help
      self.error = error
      self.content = content()
      self.footer = footer()
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(title).font(.headline.weight(.semibold))
        if let help {
          Text(help).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        content
        if let error {
          Text(error).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack(spacing: 10) { footer }
      }.padding(28).frame(minWidth: 390, idealWidth: 440, maxWidth: 520)
    }
  }

#endif
