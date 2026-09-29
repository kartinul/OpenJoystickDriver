#if canImport(AppKit)

  enum RuntimeWorkflow: CaseIterable, Sendable {
    case status
    case runtimeDiagnostics
    case controllerList
    case controllerState
    case controllerWatch
    case controllerOutput
    case controllerPackets
    case profileMapping
    case permissions
    case virtualHIDProfileOverride
    case logs
    case supportReport
    case extensionLifecycle
    case updateCheck
    case structuredOutput
    case scripting
    case soakTesting
    case catalogDiagnostics
    case packaging
    case catalogGeneration
    case driverKitGeneration
  }

  enum ProductSurface: Hashable, Sendable {
    case overview
    case controllers
    case profiles
    case console
    case developerTools
    case inputTest
    case settings
    case automationOnly
  }

  enum ProductCapabilityMatrix {
    static func destinations(for workflow: RuntimeWorkflow) -> Set<ProductSurface> {
      switch workflow {
      case .status: return [.overview]
      case .runtimeDiagnostics: return [.developerTools]
      case .controllerList: return [.controllers]
      case .controllerState, .controllerWatch, .controllerOutput: return [.inputTest]
      case .controllerPackets: return [.developerTools]
      case .profileMapping: return [.profiles]
      case .permissions, .extensionLifecycle: return [.overview]
      case .virtualHIDProfileOverride: return [.controllers]
      case .logs: return [.console]
      case .supportReport: return [.developerTools]
      case .updateCheck: return [.settings]
      case .structuredOutput, .scripting, .soakTesting, .catalogDiagnostics, .packaging,
        .catalogGeneration, .driverKitGeneration:
        return [.automationOnly]
      }
    }
  }

#endif
