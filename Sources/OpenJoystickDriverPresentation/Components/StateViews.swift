#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        OJDSystemSymbol(
          name: symbol,
          fallback: OJDLocalized.string("common.status", fallback: "Status")
        ).font(.title).foregroundColor(Color(NSColor.controlAccentColor))
        Text(title).font(.headline)
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }.padding(.vertical, 12)
    }
  }

  struct LoadingStateView: View {
    let message: String

    var body: some View {
      HStack(spacing: 8) {
        if #available(macOS 11.0, *) {
          ProgressView()
        } else {
          Text(OJDLocalized.string("common.loadingEllipsis", fallback: "..."))
        }
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }
  }

  struct ServiceFailureStateView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
      GroupBox {
        HStack(alignment: .top, spacing: 10) {
          OJDSystemSymbol(
            name: SemanticState.failure.presentation.symbolName,
            fallback: OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
          ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
          VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
            Button(OJDLocalized.string("common.tryAgain", fallback: "Try again"), action: retry)
          }
          Spacer(minLength: 0)
        }.padding(4)
      }.ojdAccessibilityLabel(title).ojdAccessibilityValue(message)
    }
  }

  struct OJDLoadingIndicator: View {
    var body: some View {
      if #available(macOS 11.0, *) {
        ProgressView()
      } else {
        Text(OJDLocalized.string("common.loadingEllipsis", fallback: "..."))
      }
    }
  }

#endif
