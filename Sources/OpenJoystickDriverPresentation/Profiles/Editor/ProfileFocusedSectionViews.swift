#if canImport(SwiftUI)
  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileCombinationsSection: View {
    let profile: RemappingProfile
    let openSheet: (ProfileEditorSheet) -> Void
    let removeChord: (UUID) -> Void
    let removeSequence: (UUID) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 18) {
        Text(OJDLocalized.string("profiles.combinations", fallback: "Combinations")).font(.headline)
        combinationGroup(
          title: OJDLocalized.string("profiles.chords", fallback: "Chords"),
          addTitle: OJDLocalized.string("profiles.addChord", fallback: "Add chord"),
          isEmpty: profile.chords.isEmpty,
          emptyMessage: OJDLocalized.string("profiles.noChords", fallback: "No chords configured."),
          add: { openSheet(.chord) },
          content: {
            ForEach(profile.chords) { chord in
              HStack {
                Text(
                  chord.sources.map(RuntimePresentation.sourceLabel).sorted().joined(
                    separator: " + "
                  )
                )
                OJDSystemSymbol(name: "arrow.right", fallback: "->")
                KeyboardDestinationLabel(destination: chord.destination)
                Spacer()
                removeButton { removeChord(chord.id) }
              }
            }
          }
        )
        combinationGroup(
          title: OJDLocalized.string("profiles.sequences", fallback: "Sequences"),
          addTitle: OJDLocalized.string("profiles.addSequence", fallback: "Add sequence"),
          isEmpty: profile.sequences.isEmpty,
          emptyMessage: OJDLocalized.string(
            "profiles.noSequences",
            fallback: "No sequences configured."
          ),
          add: { openSheet(.sequence) },
          content: {
            ForEach(profile.sequences) { sequence in
              HStack {
                Text(
                  sequence.sources.map(RuntimePresentation.sourceLabel).joined(separator: " -> ")
                )
                Text(String(format: "(%.0f ms)", sequence.windowMs)).foregroundColor(
                  Color(NSColor.secondaryLabelColor)
                )
                OJDSystemSymbol(name: "arrow.right", fallback: "->")
                KeyboardDestinationLabel(destination: sequence.destination)
                Spacer()
                removeButton { removeSequence(sequence.id) }
              }
            }
          }
        )
      }
    }

    private func combinationGroup<Content: View>(
      title: String,
      addTitle: String,
      isEmpty: Bool,
      emptyMessage: String,
      add: @escaping () -> Void,
      @ViewBuilder content: () -> Content
    ) -> some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text(title).font(.headline)
            Spacer()
            OJDCompactSymbolButton(symbolName: "plus", label: addTitle, action: add)
          }
          if isEmpty {
            Text(emptyMessage).foregroundColor(Color(NSColor.secondaryLabelColor))
          } else {
            content()
          }
        }.padding(4)
      }
    }
  }

  struct ProfileLayersSection: View {
    let profile: RemappingProfile
    let capabilities: ControllerProfileCapabilities
    let openSheet: (ProfileEditorSheet) -> Void
    let removeLayer: (UUID) -> Void
    let removeBinding: (UUID, UUID) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(OJDLocalized.string("profiles.layers", fallback: "Layers")).font(.headline)
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("profiles.addLayer", fallback: "Add layer")
          ) { openSheet(.layer) }
        }
        if profile.layers.isEmpty {
          Text(OJDLocalized.string("profiles.noLayers", fallback: "No layers configured."))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        } else {
          ForEach(profile.layers) { layer in layerGroup(layer) }
        }
      }
    }

    private func layerGroup(_ layer: RemappingLayer) -> some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(layer.name).font(.subheadline.weight(.semibold))
              Text(layerDescription(layer)).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
            Spacer()
            OJDCompactSymbolButton(
              symbolName: "plus",
              label: OJDLocalized.string("common.addAssignment", fallback: "Add assignment")
            ) { openSheet(.layerBinding(layer)) }
            OJDCompactSymbolButton(
              symbolName: "pencil",
              label: OJDLocalized.string("profiles.motion.title", fallback: "Motion tuning")
            ) { openSheet(.layerMotion(layer)) }.disabled(
              !capabilities.physicalInput.motion && layer.motionTuning == nil
            )
            removeButton { removeLayer(layer.id) }
          }
          ForEach(layer.bindings) { binding in
            HStack {
              Text(RuntimePresentation.sourceLabel(binding.source))
              OJDSystemSymbol(name: "arrow.right", fallback: "->")
              KeyboardDestinationLabel(destination: binding.destination)
              Spacer()
              if binding.axisTuning != nil {
                Button(OJDLocalized.string("common.adjust", fallback: "Adjust...")) {
                  openSheet(.layerAdjustment(layer.id, binding))
                }
              }
              Button(OJDLocalized.string("profiles.behavior", fallback: "Behavior...")) {
                openSheet(.layerBehavior(layer.id, binding))
              }
              removeButton { removeBinding(layer.id, binding.id) }
            }
          }
        }.padding(4)
      }
    }

    private func layerDescription(_ layer: RemappingLayer) -> String {
      let mode =
        layer.activationMode == .hold
        ? OJDLocalized.string("profiles.hold", fallback: "Hold")
        : OJDLocalized.string("profiles.toggle", fallback: "Toggle")
      return "\(mode): \(RuntimePresentation.sourceLabel(layer.activator))"
    }
  }

  struct ProfileControllerSection: View {
    let profile: RemappingProfile
    let capabilities: ControllerProfileCapabilities
    let openSheet: (ProfileEditorSheet) -> Void
    let updateOutputPolicy: (RemappingOutputPolicy) -> Void
    let updatePhysicalColor: (ControllerColor?) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 18) {
        Text(OJDLocalized.string("common.controller", fallback: "Controller")).font(.headline)
        detailsGroup
        outputGroup
        configurationGroup(
          title: OJDLocalized.string("profiles.motion.title", fallback: "Motion tuning"),
          summary: OJDLocalized.string("profiles.motion.space", fallback: "Coordinate space")
            + " · " + OJDLocalized.string("profiles.gyro.output", fallback: "Gyro output"),
          supported: capabilities.physicalInput.motion
        ) { openSheet(.motion) }
        configurationGroup(
          title: OJDLocalized.string("profiles.stick.title", fallback: "Stick modes"),
          summary: assignmentCountLabel(profile.stickMappings.count),
          supported: capabilities.supportsStickAxes,
          enabled: capabilities.supportsStickAxes || !profile.stickMappings.isEmpty
        ) { openSheet(.sticks) }
        configurationGroup(
          title: OJDLocalized.string("profiles.trigger.title", fallback: "Trigger stages"),
          summary: assignmentCountLabel(profile.triggerMappings.count),
          supported: capabilities.supportsAnalogTriggers,
          enabled: capabilities.supportsAnalogTriggers || !profile.triggerMappings.isEmpty
        ) { openSheet(.triggers) }
        configurationGroup(
          title: OJDLocalized.string("profiles.touch.title", fallback: "Touch mappings"),
          summary: assignmentCountLabel(profile.touchMappings.count),
          supported: !capabilities.physicalInput.touchSurfaces.isEmpty,
          enabled: capabilities.physicalInput.touchContactCount > 0
            || !profile.touchMappings.isEmpty
        ) { openSheet(.touch) }
        ProfileLightingEditor(color: profile.physicalColor, onChange: updatePhysicalColor).disabled(
          !capabilities.physicalOutput.lightingFeatures.contains(.programmableColor)
            && profile.physicalColor == nil
        )
      }
    }

    private var detailsGroup: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(OJDLocalized.string("profiles.details", fallback: "Profile details")).font(
            .subheadline.weight(.semibold)
          )
          KeyValueRow(
            label: OJDLocalized.string("common.controller", fallback: "Controller"),
            value: String(format: "%04X:%04X", profile.device.vendorID, profile.device.productID)
          )
          KeyValueRow(
            label: OJDLocalized.string("profiles.target", fallback: "Target"),
            value: RuntimePresentation.profileScopeLabel(profile.applicationScope)
          )
        }.padding(4)
      }
    }

    private var outputGroup: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Text(OJDLocalized.string("profiles.virtualOutput", fallback: "Virtual gamepad")).font(
            .subheadline.weight(.semibold)
          )
          ProfileOutputPolicyView(policy: profile.outputPolicy, onChange: updateOutputPolicy)
        }.padding(4)
      }
    }

    private func configurationGroup(
      title: String,
      summary: String,
      supported: Bool,
      enabled: Bool? = nil,
      action: @escaping () -> Void
    ) -> some View {
      GroupBox {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(
              supported
                ? summary
                : OJDLocalized.string(
                  "profiles.notSupportedByController",
                  fallback: "Not supported by this controller or protocol."
                )
            ).font(.caption).foregroundColor(
              supported ? Color(NSColor.secondaryLabelColor) : Color(NSColor.systemOrange)
            ).fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          OJDCompactSymbolButton(
            symbolName: "pencil",
            label: OJDLocalized.string("common.adjust", fallback: "Adjust")
          ) { action() }.disabled(!(enabled ?? supported))
        }.padding(4)
      }
    }

    private func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("profiles.assignments", count: count, fallback: "%d assignments")
    }
  }

  @MainActor
  private func removeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      OJDSystemSymbol(name: "minus.circle", fallback: "Remove").frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
    }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
      OJDLocalized.string("common.remove", fallback: "Remove")
    )
  }
#endif
