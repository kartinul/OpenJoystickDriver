import Foundation

struct RemappingDeviceState {
  let sessionID = UUID()
  let profile: RemappingProfile
  let identifier: DeviceIdentifier
  let passthroughBindingID = UUID()
  var motion = RemappingMotionState()
  var analog = RemappingAnalogState()
  var chords = RemappingChordState()
  var outputs = RemappingOutputState()
  var layers = RemappingLayerState()
  var activeSources: Set<RemappingSource> = []
  var sourcePressTimes: [RemappingSource: UInt64] = [:]
  var lastUptime: UInt64 = 0
  var dpadDirections: Set<RemappingDpadDirection> = []

  func binding(for source: RemappingSource) -> RemappingBinding? {
    for layerID in layers.activeLayers.reversed() {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      if let binding = layer.bindings.first(where: { $0.source == source }) { return binding }
    }
    return profile.bindings.first { $0.source == source }
  }
}
