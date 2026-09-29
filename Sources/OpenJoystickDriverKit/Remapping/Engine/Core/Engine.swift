import Foundation

/// Consumes normalized controller events and emits system and virtual gamepad actions.
///
/// The caller owns profile selection and target-application policy. An active
/// profile is supplied with each event batch. Gamepad destinations are delivered
/// through the injected virtual output sink. Time is injected as monotonic uptime
/// nanoseconds so turbo and continuous output can be tested without sleeping.
public actor RemappingEventEngine {
  let sink: any RemappingSystemInputSink
  let gamepadSink: (any RemappingGamepadSink)?
  let physicalOutputSink: (any RemappingPhysicalOutputSink)?
  var heldGamepadDevices: Set<DeviceIdentifier> = []
  var uncertainGamepadDevices: Set<DeviceIdentifier> = []
  var heldPhysicalOwners: [DeviceIdentifier: Set<UUID>] = [:]
  var uncertainPhysicalDevices: Set<DeviceIdentifier> = []
  nonisolated public let emissionBarrier: RemappingEmissionBarrier
  var state = RemappingEngineState()
  var faulted = false
  var operationInProgress = false
  var operationWaiters: [CheckedContinuation<Void, Never>] = []
  var uncertainHeldOutputs: Set<RemappingHeldOutput> = []

  public init(
    sink: any RemappingSystemInputSink,
    gamepadSink: (any RemappingGamepadSink)? = nil,
    physicalOutputSink: (any RemappingPhysicalOutputSink)? = nil,
    emissionBarrier: RemappingEmissionBarrier = RemappingEmissionBarrier()
  ) {
    self.sink = sink
    self.gamepadSink = gamepadSink
    self.physicalOutputSink = physicalOutputSink
    self.emissionBarrier = emissionBarrier
  }
}
