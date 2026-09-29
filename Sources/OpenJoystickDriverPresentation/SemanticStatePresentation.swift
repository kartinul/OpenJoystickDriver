#if canImport(AppKit)

  import AppKit

  enum SemanticTone: String, CaseIterable, Sendable {
    case positive
    case attention
    case failure
    case neutral
    case selection

    static let caution = Self.attention

    var color: NSColor {
      switch self {
      case .positive: return .systemGreen
      case .attention: return .systemOrange
      case .failure: return .systemRed
      case .neutral: return .secondaryLabelColor
      case .selection: return .controlAccentColor
      }
    }
  }

  enum SemanticState: String, CaseIterable, Sendable {
    case active
    case healthy
    case attention
    case failure
    case inactive
    case loading
    case disconnected
    case unknown
    case dirty
    case saved
    case capturing

    var presentation: SemanticStatePresentation {
      switch self {
      case .active: return .init(tone: .positive, symbolName: "checkmark.circle.fill")
      case .healthy: return .init(tone: .positive, symbolName: "checkmark.circle")
      case .attention: return .init(tone: .attention, symbolName: "exclamationmark.circle")
      case .failure: return .init(tone: .failure, symbolName: "exclamationmark.triangle")
      case .inactive: return .init(tone: .neutral, symbolName: "circle")
      case .loading: return .init(tone: .neutral, symbolName: "clock")
      case .disconnected: return .init(tone: .neutral, symbolName: "cable.connector.slash")
      case .unknown: return .init(tone: .neutral, symbolName: "questionmark.circle")
      case .dirty: return .init(tone: .attention, symbolName: "pencil.circle")
      case .saved: return .init(tone: .positive, symbolName: "checkmark.circle")
      case .capturing: return .init(tone: .positive, symbolName: "record.circle")
      }
    }
  }

  struct SemanticStatePresentation: Equatable, Sendable {
    let tone: SemanticTone
    let symbolName: String
  }

  enum SystemSymbolResolution: Equatable, Sendable {
    case symbol(String)
    case text
  }

  enum SystemSymbolPolicy {
    static func resolution(
      preferred: String,
      fallback: String?,
      preferredIsAvailable: Bool,
      fallbackIsAvailable: Bool
    ) -> SystemSymbolResolution {
      if preferredIsAvailable { return .symbol(preferred) }
      if let fallback, fallbackIsAvailable { return .symbol(fallback) }
      return .text
    }
  }

#endif
