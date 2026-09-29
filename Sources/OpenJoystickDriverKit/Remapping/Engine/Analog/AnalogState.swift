import Foundation

struct RemappingAnalogState {
  var sticks: [RemappingStickSource: RemappingStickRuntime] = [:]
  var triggers: [RemappingTriggerSource: RemappingDualStageTriggerRuntime] = [:]
  var touchSurfaces: [RemappingTouchSurface: RemappingTouchSurfaceState] = [:]
  var physicalAxes: [RemappingAxis: Float] = [:]
  var virtualAxisBindings: Set<UUID> = []
}
