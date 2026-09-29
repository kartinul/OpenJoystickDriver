#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension CaptureAssignmentSheet {

    private var captureStatusAccessibilityValue: String {
      switch viewModel.inputCaptureState {
      case .idle: return OJDLocalized.string("capture.ready", fallback: "Ready to listen.")
      case .listening:
        return OJDLocalized.string(
          "capture.listening",
          fallback: "Listening for a controller control."
        )
      case .received(let selector, let state):
        if let detected = RuntimePresentation.detectedSource(
          from: state,
          labels: viewModel.buttonLabels(for: selector)
        ) {
          return OJDLocalized.formatted(
            "capture.detected",
            fallback: "Detected: %@.",
            RuntimePresentation.sourceLabel(detected)
          )
        }
        return OJDLocalized.string(
          "capture.noSupported",
          fallback: "Input received, but no supported control was identified."
        )
      case .detected(_, _, let detected):
        return OJDLocalized.formatted(
          "capture.detectedWithDestination",
          fallback: "Detected: %@. %@",
          RuntimePresentation.sourceLabel(detected),
          OJDLocalized.string(
            "capture.destinationReady",
            fallback: "Destination is ready for selection."
          )
        )
      case .unavailable(_, let message), .error(_, let message): return message
      }
    }

    func announceCaptureState(_ captureState: RuntimeInputCaptureState) {
      let message: String
      switch captureState {
      case .idle, .received: return
      case .listening:
        message = OJDLocalized.string(
          "capture.listeningCancel",
          fallback: "Listening for a controller control. Press Escape to cancel."
        )
      case .detected(let selector, _, let detected):
        guard selectedDeviceSelector == selector else { return }
        message = OJDLocalized.formatted(
          "capture.detectedWithDestination",
          fallback: "Detected: %@. %@",
          RuntimePresentation.sourceLabel(detected),
          OJDLocalized.string(
            "capture.destinationReady",
            fallback: "Destination is ready for selection."
          )
        )
      case .unavailable(_, let detail): message = detail
      case .error(_, let detail):
        message = OJDLocalized.formatted("capture.error", fallback: "Capture error. %@", detail)
      }
      NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }

    @ViewBuilder
    var captureStatus: some View {
      Group {
        switch viewModel.inputCaptureState {
        case .idle: EmptyView()
        case .listening:
          Text(
            OJDLocalized.string(
              "capture.listeningEllipsis",
              fallback: "Listening for a controller control..."
            )
          )
        case .received(let selector, let state):
          VStack(alignment: .leading, spacing: 3) {
            if let detected = RuntimePresentation.detectedSource(
              from: state,
              labels: viewModel.buttonLabels(for: selector)
            ) {
              Text(
                OJDLocalized.formatted(
                  "capture.detectedNoPeriod",
                  fallback: "Detected: %@",
                  RuntimePresentation.sourceLabel(detected)
                )
              ).font(.subheadline.weight(.semibold))
            } else {
              Text(
                OJDLocalized.string(
                  "capture.noSupported",
                  fallback: "Input received, but no supported control was identified."
                )
              ).font(.subheadline.weight(.semibold))
            }
            Text(heldControlsText(state))
          }
        case .detected(_, let state, let detected):
          VStack(alignment: .leading, spacing: 3) {
            Text(
              OJDLocalized.formatted(
                "capture.detectedNoPeriod",
                fallback: "Detected: %@",
                RuntimePresentation.sourceLabel(detected)
              )
            ).font(.subheadline.weight(.semibold))
            Text(heldControlsText(state))
          }
        case .unavailable(_, let message), .error(_, let message):
          Text(message).foregroundColor(Color(NSColor.systemRed))
        }
      }.ojdAccessibilityLabel(OJDLocalized.string("capture.status", fallback: "Capture status"))
        .ojdAccessibilityValue(captureStatusAccessibilityValue)
    }
    private func heldControlsText(_ state: ControllerState) -> String {
      let held = ControlID.allCases.filter(state.pressed.contains)
      guard !held.isEmpty else {
        return OJDLocalized.string("capture.noButton", fallback: "No button is currently held.")
      }
      return OJDLocalized.formatted(
        "capture.buttonsHeld",
        fallback: "Buttons held: %@",
        held.map(\.rawValue).joined(separator: ", ")
      )
    }
  }

#endif
