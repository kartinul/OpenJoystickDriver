#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension BindingBehaviorSheet {
    typealias SaveAction = (
      RemappingBindingBehavior, Double, RemappingTurbo?, RemappingLongHold?, RemappingDoubleTap?,
      [RemappingAction]
    ) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.bindingBehavior", fallback: "Assignment behavior")).font(
          .headline.weight(.semibold)
        )
        Picker(
          OJDLocalized.string("profiles.bindingBehavior", fallback: "Assignment behavior"),
          selection: $behavior
        ) {
          Text(OJDLocalized.string("profiles.hold", fallback: "Hold")).tag(
            RemappingBindingBehavior.hold
          )
          Text(OJDLocalized.string("profiles.toggle", fallback: "Toggle")).tag(
            RemappingBindingBehavior.toggle
          )
          Text(OJDLocalized.string("profiles.tapOnPress", fallback: "Tap on press")).tag(
            RemappingBindingBehavior.tapOnPress
          )
          Text(OJDLocalized.string("profiles.tapOnRelease", fallback: "Tap on release")).tag(
            RemappingBindingBehavior.tapOnRelease
          )
          Text(OJDLocalized.string("profiles.pulse", fallback: "Pulse")).tag(
            RemappingBindingBehavior.pulse
          )
          Text(OJDLocalized.string("profiles.pressOnly", fallback: "Press only")).tag(
            RemappingBindingBehavior.press
          )
          Text(OJDLocalized.string("profiles.releaseOnly", fallback: "Release only")).tag(
            RemappingBindingBehavior.release
          )
        }.disabled(
          binding.destination.isContinuous || turboEnabled || longHoldEnabled || doubleTapEnabled
        )
        if behavior == .pulse {
          valueSlider(
            title: OJDLocalized.string("profiles.pulseDuration", fallback: "Pulse duration"),
            value: $pulseDurationMs,
            range: RemappingBinding.pulseDurationRange,
            format: "%.0f ms"
          )
        }
        if showsAdditionalActions {
          ProfileAdditionalActionsView(
            source: binding.source,
            capabilities: capabilities,
            actions: $additionalActions
          )
        }
        Toggle(OJDLocalized.string("profiles.turbo", fallback: "Turbo"), isOn: $turboEnabled)
          .disabled(
            !binding.destination.acceptsTurbo || longHoldEnabled || doubleTapEnabled
              || behavior != .hold
          )
        if turboEnabled {
          valueSlider(
            title: OJDLocalized.string("profiles.turboRate", fallback: "Repeat rate"),
            value: $turboRate,
            range: RemappingTurbo.repeatRateHzRange,
            format: "%.0f Hz"
          )
          valueSlider(
            title: OJDLocalized.string("profiles.turboDuty", fallback: "Duty cycle"),
            value: $turboDuty,
            range: RemappingTurbo.dutyCycleRange,
            format: "%.0f%%",
            multiplier: 100
          )
        }
        Divider()
        Toggle(
          OJDLocalized.string("profiles.longHold", fallback: "Long hold"),
          isOn: $longHoldEnabled
        ).disabled(!supportsActivation || turboEnabled || behavior != .hold)
        if longHoldEnabled {
          valueSlider(
            title: OJDLocalized.string("profiles.holdDuration", fallback: "Hold duration"),
            value: $longHoldDuration,
            range: RemappingLongHold.durationRange,
            format: "%.0f ms"
          )
          destinationPicker(selection: $longHoldDestination)
        }
        Toggle(
          OJDLocalized.string("profiles.doubleTap", fallback: "Double tap"),
          isOn: $doubleTapEnabled
        ).disabled(!supportsActivation || turboEnabled || behavior != .hold)
        if doubleTapEnabled {
          valueSlider(
            title: OJDLocalized.string("profiles.tapWindow", fallback: "Tap window"),
            value: $doubleTapWindow,
            range: RemappingDoubleTap.windowRange,
            format: "%.0f ms"
          )
          destinationPicker(selection: $doubleTapDestination)
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) { dismiss() }
          Button(OJDLocalized.string("common.apply", fallback: "Apply")) {
            onSave(
              behavior,
              pulseDurationMs,
              turboEnabled ? RemappingTurbo(repeatRateHz: turboRate, dutyCycle: turboDuty) : nil,
              longHoldEnabled
                ? RemappingLongHold(durationMs: longHoldDuration, destination: longHoldDestination)
                : nil,
              doubleTapEnabled
                ? RemappingDoubleTap(windowMs: doubleTapWindow, destination: doubleTapDestination)
                : nil,
              additionalActions
            )
            dismiss()
          }
        }
      }.padding(28).frame(width: 470)
    }

    private var supportsActivation: Bool {
      switch binding.source {
      case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
        return !binding.destination.isContinuous
      case .axis, .axisDirection: return false
      }
    }

    private func valueSlider(
      title: String,
      value: Binding<Double>,
      range: ClosedRange<Double>,
      format: String,
      multiplier: Double = 1
    ) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(String(format: format, value.wrappedValue * multiplier)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range).ojdAccessibilityLabel(title)
      }
    }

    private func destinationPicker(selection: Binding<RemappingDestination>) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        Picker(
          OJDLocalized.string("common.destination", fallback: "Destination"),
          selection: selection
        ) {
          ForEach(discreteDestinations(including: selection.wrappedValue), id: \.destination) {
            Text($0.title).tag($0.destination)
          }
        }
        PhysicalOutputDestinationFields(destination: selection)
      }
    }

    func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

#endif
