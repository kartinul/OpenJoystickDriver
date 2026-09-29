#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct PageHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
      self.title = title
      self.subtitle = subtitle
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.largeTitle.weight(.semibold))
        if let subtitle {
          Text(subtitle).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
      }
    }
  }

  struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(label).foregroundColor(Color(NSColor.secondaryLabelColor))
        Spacer(minLength: 8)
        Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
      }
    }
  }

#endif
