import Foundation

struct RemappingOutputState {
  var gamepad = RemappingGamepadAccumulator()
  var heldBindings: [UUID: RemappingDestination] = [:]
  var armedReleaseBindings: Set<UUID> = []
  var pulseDeadlines: [UUID: UInt64] = [:]
  var turbos: [UUID: RemappingTurboOutput] = [:]
  var continuous: [UUID: RemappingContinuousOutput] = [:]
  var activations: [UUID: RemappingActivationTracker] = [:]
}

struct RemappingActivationTracker {
  var pressUptime: UInt64?
  var releaseUptime: UInt64?
  var tapCount: Int = 0
  var firedBindingID: UUID?
  var pendingDefault: Bool = false
}
