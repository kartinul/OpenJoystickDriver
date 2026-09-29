import Foundation

struct RemappingMotionState {
  var motion = RemappingMotionProcessor()
  let gyroBindingID = UUID()
  let motionSteeringBindingID = UUID()
  var gyroDeadline: UInt64?
  var motionStickDeadline: UInt64?
  var gyroToggleActive = false
  var gyroAwaitingBaseline = true
  var gyroTrackball = RemappingMotionTrackball()
  var activeMotionLeans: Set<RemappingMotionLeanDirection> = []
}
