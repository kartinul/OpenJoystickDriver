import Foundation

struct RemappingDeviceState {
  let sessionID = UUID()
  var motion = RemappingMotionProcessor()
  let gyroBindingID = UUID()
  let motionSteeringBindingID = UUID()
  var gyroDeadline: UInt64?
  var motionStickDeadline: UInt64?
  var gyroToggleActive = false
  var gyroAwaitingBaseline = true
  var gyroTrackball = RemappingMotionTrackball()
  var activeMotionLeans: Set<RemappingMotionLeanDirection> = []
  var sticks: [RemappingStickSource: RemappingStickRuntime] = [:]
  var triggers: [RemappingTriggerSource: RemappingDualStageTriggerRuntime] = [:]
  var touchSurfaces: [RemappingTouchSurface: RemappingTouchSurfaceState] = [:]
  let profile: RemappingProfile
  let identifier: DeviceIdentifier
  var gamepad = RemappingGamepadAccumulator()
  var virtualAxisBindings: Set<UUID> = []
  let passthroughBindingID = UUID()
  var physicalAxes: [RemappingAxis: Float] = [:]
  var activeSources: Set<RemappingSource> = []
  var sourcePressTimes: [RemappingSource: UInt64] = [:]
  var lastUptime: UInt64 = 0
  var pendingChordPresses: [RemappingPendingChordPress] = []
  var consumedChordSources: Set<RemappingSource> = []
  var replayedChordSources: Set<RemappingSource> = []
  var dpadDirections: Set<RemappingDpadDirection> = []
  var heldBindings: [UUID: RemappingDestination] = [:]
  var armedReleaseBindings: Set<UUID> = []
  var pulseDeadlines: [UUID: UInt64] = [:]
  var turbos: [UUID: RemappingTurboOutput] = [:]
  var continuous: [UUID: RemappingContinuousOutput] = [:]
  var activations: [UUID: RemappingActivationTracker] = [:]
  var activeChords: Set<UUID> = []
  var sequenceHistory: [RemappingSequenceHistoryEntry] = []
  var deferredSequences: [RemappingDeferredSequence] = []
  var activeLayers: [UUID] = []
  var layerToggleState: Set<UUID> = []

  func binding(for source: RemappingSource) -> RemappingBinding? {
    for layerID in activeLayers.reversed() {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      if let binding = layer.bindings.first(where: { $0.source == source }) { return binding }
    }
    return profile.bindings.first { $0.source == source }
  }
}

struct RemappingActivationTracker {
  var pressUptime: UInt64?
  var releaseUptime: UInt64?
  var tapCount: Int = 0
  var firedBindingID: UUID?
  var pendingDefault: Bool = false
}

struct RemappingSequenceHistoryEntry: Equatable {
  let source: RemappingSource
  let uptime: UInt64
  var awaitingChord: Bool = false
}
