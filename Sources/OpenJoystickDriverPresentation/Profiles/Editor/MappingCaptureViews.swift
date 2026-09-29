#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Axis adjustment and capture

  struct AxisAdjustmentSheet: View {
    let binding: RemappingBinding
    let onSave: (RemappingAxisTuning) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var deadzone: Double
    @State
    private var gain: Double
    @State
    private var inverted: Bool
    @State
    private var curve: RemappingResponseCurve
    @State
    private var threshold: Double

    init(binding: RemappingBinding, onSave: @escaping (RemappingAxisTuning) -> Void) {
      self.binding = binding
      self.onSave = onSave
      let tuning = binding.axisTuning ?? .default
      _deadzone = State(initialValue: tuning.deadzone)
      _gain = State(initialValue: tuning.gain)
      _inverted = State(initialValue: tuning.inverted)
      _curve = State(initialValue: tuning.responseCurve)
      _threshold = State(initialValue: tuning.digitalActivationThreshold)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(
          OJDLocalized.formatted(
            "capture.adjust",
            fallback: "Adjust %@",
            RuntimePresentation.sourceLabel(binding.source)
          )
        ).font(.headline.weight(.semibold))
        SliderRow(
          title: OJDLocalized.string("capture.deadZone", fallback: "Dead zone"),
          value: $deadzone,
          range: RemappingAxisTuning.deadzoneRange,
          suffix: "%"
        )
        SliderRow(
          title: OJDLocalized.string("capture.gain", fallback: "Gain"),
          value: $gain,
          range: RemappingAxisTuning.gainRange,
          suffix: "×"
        )
        Toggle(OJDLocalized.string("capture.invertAxis", fallback: "Invert axis"), isOn: $inverted)
        Picker(
          OJDLocalized.string("capture.responseCurve", fallback: "Response curve"),
          selection: $curve
        ) {
          ForEach(RemappingResponseCurve.allCases, id: \.self) { value in
            Text(responseCurveLabel(value)).tag(value)
          }
        }
        SliderRow(
          title: OJDLocalized.string("capture.digitalThreshold", fallback: "Digital threshold"),
          value: $threshold,
          range: RemappingAxisTuning.digitalActivationThresholdRange,
          suffix: "%"
        )
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save", fallback: "Save")) {
            onSave(
              RemappingAxisTuning(
                deadzone: deadzone,
                gain: gain,
                inverted: inverted,
                responseCurve: curve,
                digitalActivationThreshold: threshold
              )
            )
            presentationMode.wrappedValue.dismiss()
          }
        }
      }.padding(28).frame(width: 430)
    }

    private func responseCurveLabel(_ value: RemappingResponseCurve) -> String {
      switch value {
      case .linear: return OJDLocalized.string("capture.linear", fallback: "Linear")
      case .easeIn: return OJDLocalized.string("capture.easeIn", fallback: "Ease in")
      case .easeOut: return OJDLocalized.string("capture.easeOut", fallback: "Ease out")
      case .smoothStep: return OJDLocalized.string("capture.smoothStep", fallback: "Smooth step")
      }
    }
  }

  private struct SliderRow: View {
    let title: String
    @Binding
    var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(formattedValue).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Slider(value: $value, in: range)
      }
    }

    private var formattedValue: String {
      let percent = suffix == "%"
      let value = percent ? value * 100 : value
      return String(format: percent ? "%.0f%@" : "%.1f%@", value, suffix)
    }
  }

  struct ConflictBanner: View {
    let reload: () -> Void
    let keepEditing: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        Text(
          OJDLocalized.string(
            "error.profileChanged",
            fallback: "This profile changed elsewhere. Reload or keep editing."
          )
        ).font(.subheadline.weight(.semibold))
        HStack(spacing: 10) {
          Button(OJDLocalized.string("common.reload", fallback: "Reload")) { reload() }
          Button(OJDLocalized.string("common.keepEditing", fallback: "Keep editing")) {
            keepEditing()
          }
        }
      }.padding(10).background(
        RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor))
      )
    }
  }

  enum ProfileNameValidation {
    static func trimmedName(_ name: String) -> String {
      name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  struct ProfileNameSheet: View {
    let title: String
    let initialName: String
    let devices: [ApplicationServiceDeviceDescription]
    let onCreate: (String, RemappingDeviceScope, RemappingApplicationScope) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var name: String
    @State
    private var selectedRuntimeIdentifier: String?
    @State
    private var vendorID = ""
    @State
    private var productID = ""
    @State
    private var scopeKind = ProfileScopeKind.global
    @State
    private var bundleIdentifier = ""

    init(
      title: String,
      initialName: String,
      devices: [ApplicationServiceDeviceDescription],
      onCreate: @escaping (String, RemappingDeviceScope, RemappingApplicationScope) -> Void
    ) {
      self.title = title
      self.initialName = initialName
      self.devices = devices
      self.onCreate = onCreate
      _name = State(initialValue: initialName)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.headline.weight(.semibold))
        TextField(OJDLocalized.string("common.profileName", fallback: "Profile name"), text: $name)
          .textFieldStyle(RoundedBorderTextFieldStyle())
        if !name.isEmpty && trimmedName.isEmpty {
          Text(
            OJDLocalized.string("capture.profileNameValidation", fallback: "Enter a profile name.")
          ).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          ).ojdAccessibilityLabel(
            OJDLocalized.string("capture.profileNameValidation", fallback: "Enter a profile name.")
          )
        }
        if !devices.isEmpty {
          Picker(
            OJDLocalized.string("common.controller", fallback: "Controller"),
            selection: selectedDeviceBinding
          ) {
            Text(OJDLocalized.string("profiles.manualDevice", fallback: "Manual identifiers")).tag(
              Self.manualDeviceIdentifier
            )
            ForEach(devices, id: \.runtimeIdentifier) { device in
              Text(device.name).tag(device.runtimeIdentifier)
            }
          }
        }
        HStack(spacing: 12) {
          TextField(
            OJDLocalized.string("profiles.vendorID", fallback: "Vendor ID"),
            text: $vendorID
          )
          TextField(
            OJDLocalized.string("profiles.productID", fallback: "Product ID"),
            text: $productID
          )
        }
        Text(
          OJDLocalized.string(
            "profiles.identifierHint",
            fallback: "Use decimal or 0x-prefixed hexadecimal identifiers."
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker(OJDLocalized.string("profiles.target", fallback: "Target"), selection: $scopeKind) {
          Text(OJDLocalized.string("profiles.targetGlobal", fallback: "All applications")).tag(
            ProfileScopeKind.global
          )
          Text(OJDLocalized.string("profiles.targetApplication", fallback: "One application")).tag(
            ProfileScopeKind.application
          )
        }
        if scopeKind == .application {
          TextField(
            OJDLocalized.string("profiles.bundleIdentifier", fallback: "Bundle identifier"),
            text: $bundleIdentifier
          )
        }
        if !fieldsAreEmpty && proposedProfile == nil {
          Text(
            OJDLocalized.string(
              "profiles.creationValidation",
              fallback: "Review the profile name, controller identifiers, and application target."
            )
          ).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.create", fallback: "Create")) {
            guard let proposedProfile else { return }
            onCreate(proposedProfile.name, proposedProfile.device, proposedProfile.applicationScope)
            presentationMode.wrappedValue.dismiss()
          }.disabled(!canCreate)
        }
      }.padding(28).frame(width: 390).onAppear {
        selectedRuntimeIdentifier = devices.first?.runtimeIdentifier
        applySelectedDevice(devices.first)
      }
    }

    private var trimmedName: String { ProfileNameValidation.trimmedName(name) }

    private var canCreate: Bool { proposedProfile != nil }

    private var fieldsAreEmpty: Bool {
      name.isEmpty && vendorID.isEmpty && productID.isEmpty && bundleIdentifier.isEmpty
    }

    private var proposedProfile: RemappingProfile? {
      guard let vendorID = ProfileIdentifierInput.parse(vendorID),
        let productID = ProfileIdentifierInput.parse(productID)
      else { return nil }
      let applicationScope: RemappingApplicationScope
      switch scopeKind {
      case .global: applicationScope = .global
      case .application: applicationScope = .application(bundleIdentifier: bundleIdentifier)
      }
      let profile = RemappingProfile(
        name: trimmedName,
        device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
        applicationScope: applicationScope,
        bindings: []
      )
      guard (try? profile.validate()) != nil else { return nil }
      return profile
    }

    private var selectedDeviceBinding: Binding<String> {
      Binding(
        get: { selectedRuntimeIdentifier ?? Self.manualDeviceIdentifier },
        set: { identifier in
          selectedRuntimeIdentifier = identifier
          applySelectedDevice(devices.first { $0.runtimeIdentifier == identifier })
        }
      )
    }

    private func applySelectedDevice(_ device: ApplicationServiceDeviceDescription?) {
      guard let device else { return }
      vendorID = ProfileIdentifierInput.formatted(device.vendorID)
      productID = ProfileIdentifierInput.formatted(device.productID)
    }

    private static let manualDeviceIdentifier = "manual"
  }

#endif
