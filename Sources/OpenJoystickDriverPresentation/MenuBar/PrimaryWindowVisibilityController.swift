#if canImport(AppKit)

  import AppKit

  @MainActor
  final class PrimaryWindowVisibilityController {
    enum Window: Hashable {
      case workbench
      case inputTest
    }

    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private var openWindows: Set<Window> = []
    private(set) var appliedPolicy = NSApplication.ActivationPolicy.accessory

    init(
      setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = {
        NSApplication.shared.setActivationPolicy($0)
      }
    ) { self.setActivationPolicy = setActivationPolicy }

    func opened(_ window: Window) {
      openWindows.insert(window)
      reconcileActivationPolicy()
    }

    func closed(_ window: Window) {
      openWindows.remove(window)
      reconcileActivationPolicy()
    }

    func isOpen(_ window: Window) -> Bool { openWindows.contains(window) }

    private func reconcileActivationPolicy() {
      let desiredPolicy: NSApplication.ActivationPolicy =
        openWindows.isEmpty ? .accessory : .regular
      guard desiredPolicy != appliedPolicy, setActivationPolicy(desiredPolicy) else { return }
      appliedPolicy = desiredPolicy
    }
  }

#endif
