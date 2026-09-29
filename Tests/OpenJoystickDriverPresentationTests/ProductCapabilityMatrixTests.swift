import Testing

@testable import OpenJoystickDriverPresentation

struct ProductCapabilityMatrixTests {
  @Test
  func everyRuntimeWorkflowHasOneExplicitProductClassification() {
    for workflow in RuntimeWorkflow.allCases {
      #expect(!ProductCapabilityMatrix.destinations(for: workflow).isEmpty)
    }
  }

  @Test
  func consumerWorkflowsHaveWorkbenchDestinations() {
    let expected: [RuntimeWorkflow: Set<ProductSurface>] = [
      .status: [.overview], .runtimeDiagnostics: [.developerTools], .controllerList: [.controllers],
      .controllerState: [.inputTest], .controllerWatch: [.inputTest],
      .controllerOutput: [.inputTest], .controllerPackets: [.developerTools],
      .profileMapping: [.profiles], .permissions: [.overview],
      .virtualHIDProfileOverride: [.controllers], .logs: [.console],
      .supportReport: [.developerTools], .extensionLifecycle: [.overview],
      .updateCheck: [.settings],
    ]

    for (workflow, destinations) in expected {
      #expect(ProductCapabilityMatrix.destinations(for: workflow) == destinations)
    }
  }

  @Test
  func headlessWorkflowsRemainAutomationOnly() {
    let automation: [RuntimeWorkflow] = [
      .structuredOutput, .scripting, .soakTesting, .catalogDiagnostics, .packaging,
      .catalogGeneration, .driverKitGeneration,
    ]
    for workflow in automation {
      #expect(ProductCapabilityMatrix.destinations(for: workflow) == [.automationOnly])
    }
  }

  @Test
  @MainActor
  func menuBarPublishesOneCombinedSummaryWithASemanticSignal() {
    let runtime = RuntimeViewModel(gateway: GatewayStub())
    let menuBar = MenuBarViewModel(runtime: runtime)

    #expect(menuBar.summarySemanticState == .loading)
    #expect(menuBar.summaryTitle.split(separator: "·").count == 3)
  }
}
