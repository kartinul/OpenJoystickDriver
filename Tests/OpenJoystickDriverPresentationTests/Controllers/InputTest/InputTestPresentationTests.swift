import AppKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct InputTestPresentationTests {
  @Test
  func inputTestWindowUsesTheRequestedStableSizing() {
    #expect(InputTestWindowSizingPolicy.defaultContentSize == NSSize(width: 900, height: 620))
    #expect(InputTestWindowSizingPolicy.minimumContentSize == NSSize(width: 700, height: 500))
    #expect(
      InputTestWindowSizingPolicy.fittingContentSize(NSSize(width: 640, height: 420))
        == InputTestWindowSizingPolicy.minimumContentSize
    )
  }

  @Test
  func layoutContainsEverySectionAndCompactsAtNarrowWidths() {
    #expect(InputTestLayoutPolicy.sectionOrder == [.liveInput, .axes, .motion, .rumble, .lighting])
    #expect(InputTestLayoutPolicy.widthClass(for: 700) == .compact)
    #expect(InputTestLayoutPolicy.widthClass(for: 860) == .regular)
    #expect(InputTestLayoutPolicy.widthClass(for: 1_200) == .wide)
  }

  @Test
  func controlsOutsideTheDrawnClustersAreListedAsAdditional() {
    var state = ControllerState.neutral
    state.hat = .north
    state.pressed = [
      .leftShoulder, .leftStickClick, .leftTriggerButton, .auxiliary1, .auxiliary2, .paddleLeft1,
      .paddleRight1, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .microphone,
    ]

    #expect(
      InputTestButtonPresentation.additionalControls(in: state, labels: .standard) == [
        .microphone, .paddleLeft1, .paddleRight1, .auxiliary1, .auxiliary2, .auxiliary3,
        .auxiliary4, .auxiliary5, .auxiliary6,
      ]
    )
    #expect(
      InputTestButtonPresentation.localizedTitle(for: .auxiliary1, labels: .playStation)
        == RuntimePresentation.sourceLabel(.button(.leftFunction))
    )
  }

  @Test
  func controllerFamiliesSelectProtocolAppropriateInputSymbols() {
    let xbox = InputTestControllerSymbolSet.resolve(for: .xbox)
    #expect(xbox.leftShoulder.symbol == "lb.button.roundedbottom.horizontal")
    #expect(xbox.leftTrigger.symbol == "lt.button.roundedtop.horizontal")
    #expect(xbox.guide.symbol == "xbox.logo")
    #expect(xbox.leftStickClick.symbol == "lsb.button.angledbottom.horizontal.left")

    let generic = InputTestControllerSymbolSet.resolve(for: .generic)
    #expect(generic.leftShoulder.symbol == nil)
    #expect(generic.leftShoulder.fallbackText == "LB / L1")
    #expect(generic.guide.symbol == "house.fill")
  }

  @Test
  func viewSlotShowsViewUnlessPlayStationCreatePublishesAsShare() {
    #expect(InputTestSystemClusterLayout.viewControls(labels: .standard) == [.view])
    #expect(InputTestSystemClusterLayout.viewControls(labels: .nintendo) == [.view])
    #expect(InputTestSystemClusterLayout.viewControls(labels: .playStation).isEmpty)
  }

  @Test
  func shareAndCaptureAreListedAsAdditional() {
    var state = ControllerState.neutral
    state.pressed = [.view, .guide, .share, .capture]

    #expect(
      InputTestButtonPresentation.additionalControls(in: state, labels: .standard) == [
        .share, .capture,
      ]
    )
    #expect(
      InputTestButtonPresentation.additionalControls(in: state, labels: .playStation) == [
        .view, .share, .capture,
      ]
    )
  }
}
