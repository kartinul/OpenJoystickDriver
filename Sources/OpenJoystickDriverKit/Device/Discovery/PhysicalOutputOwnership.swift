import Foundation

enum PhysicalOutputChannel: Equatable, Hashable, Sendable {
  case rumble(PhysicalRumbleMotor)
  case playerIndicator
  case color
  case brightness
  case adaptiveTrigger(PhysicalAdaptiveTrigger)

  var sortKey: String {
    switch self {
    case .rumble(let motor): "rumble:\(motor.rawValue)"
    case .playerIndicator: "player"
    case .color: "color"
    case .brightness: "brightness"
    case .adaptiveTrigger(let trigger): "adaptive:\(trigger.rawValue)"
    }
  }
}

extension RemappingPhysicalOutput {
  var channel: PhysicalOutputChannel {
    switch self {
    case .rumble(let motor, _): .rumble(motor)
    case .playerIndicator: .playerIndicator
    case .color: .color
    case .brightness: .brightness
    case .adaptiveTrigger(let trigger, _): .adaptiveTrigger(trigger)
    }
  }

  var isNeutral: Bool {
    switch self {
    case .rumble(_, let intensity), .brightness(let intensity): intensity == 0
    case .playerIndicator(let indicator): indicator == .off
    case .color(let red, let green, let blue): red == 0 && green == 0 && blue == 0
    case .adaptiveTrigger(_, let effect): effect.kind == .off
    }
  }
}

struct PhysicalOutputOwnership {
  struct Claim: Sendable {
    let output: RemappingPhysicalOutput
    let sequence: UInt64
  }

  private var nextSequence: UInt64 = 0
  private var mappingClaims: [DeviceIdentifier: [PhysicalOutputChannel: [UUID: Claim]]] = [:]
  /// Each channel's manual claims, oldest first: the newest wins, a failed command withdraws only
  /// its own, and a delivered one drops the older ones it replaced.
  private var manualClaims: [DeviceIdentifier: [PhysicalOutputChannel: [Claim]]] = [:]
  private var temporaryColorPreviews: [DeviceIdentifier: [UUID: Claim]] = [:]
  private var profileBaselines: [DeviceIdentifier: RemappingPhysicalOutput] = [:]
  /// Counts the clearings of each controller's claims and of all claims, so a state captured
  /// before a clearing (neutralization, disconnect, teardown) is never restored after it.
  private var deviceClearings: [DeviceIdentifier: UInt64] = [:]
  private var allClearings: UInt64 = 0

  var mappingClaimCount: Int {
    mappingClaims.values.reduce(0) { deviceTotal, channels in
      deviceTotal + channels.values.reduce(0) { $0 + $1.count }
    }
  }

  @discardableResult
  mutating func setMapping(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) -> PhysicalOutputChannel {
    let channel = output.channel
    if active {
      nextSequence &+= 1
      mappingClaims[identifier, default: [:]][channel, default: [:]][owner] = Claim(
        output: output,
        sequence: nextSequence
      )
    } else {
      mappingClaims[identifier]?[channel]?.removeValue(forKey: owner)
      removeEmptyMappingStorage(for: identifier, channel: channel)
    }
    return channel
  }

  mutating func releaseMappings(for identifier: DeviceIdentifier) -> Set<PhysicalOutputChannel> {
    guard let claims = mappingClaims.removeValue(forKey: identifier) else { return [] }
    return Set(claims.keys)
  }

  /// Adds one command's manual claims under one sequence and returns it, for `commitManual` or
  /// `withdrawManual` once the command's write finishes. A neutral claim lets mapping claims show
  /// through, except a colour, where black is a real claim.
  @discardableResult
  mutating func setManual(
    _ outputs: [RemappingPhysicalOutput],
    for identifier: DeviceIdentifier
  ) -> UInt64 {
    nextSequence &+= 1
    for output in outputs {
      manualClaims[identifier, default: [:]][output.channel, default: []].append(
        Claim(output: output, sequence: nextSequence)
      )
    }
    return nextSequence
  }

  @discardableResult
  mutating func setManual(
    _ output: RemappingPhysicalOutput,
    for identifier: DeviceIdentifier
  ) -> UInt64 { setManual([output], for: identifier) }

  /// Drops the claims older than the delivered claim `sequence` on `channels`.
  mutating func commitManual(
    _ sequence: UInt64,
    on channels: Set<PhysicalOutputChannel>,
    for identifier: DeviceIdentifier
  ) {
    for channel in channels
    where manualClaims[identifier]?[channel]?.contains(where: { $0.sequence == sequence }) == true {
      manualClaims[identifier]?[channel]?.removeAll { $0.sequence < sequence }
    }
  }

  /// Removes the failed claim `sequence` from `channels`, and returns whether it was the newest
  /// claim on any of them, so the channel's effective output may have changed.
  mutating func withdrawManual(
    _ sequence: UInt64,
    on channels: Set<PhysicalOutputChannel>,
    for identifier: DeviceIdentifier
  ) -> Bool {
    var wasNewest = false
    for channel in channels {
      guard let claims = manualClaims[identifier]?[channel],
        let index = claims.firstIndex(where: { $0.sequence == sequence })
      else { continue }
      if index == claims.count - 1 { wasNewest = true }
      manualClaims[identifier]?[channel]?.remove(at: index)
      removeEmptyManualStorage(for: identifier, channel: channel)
    }
    return wasNewest
  }

  mutating func setTemporaryColor(
    _ output: RemappingPhysicalOutput,
    token: UUID,
    for identifier: DeviceIdentifier
  ) {
    nextSequence &+= 1
    temporaryColorPreviews[identifier, default: [:]][token] = Claim(
      output: output,
      sequence: nextSequence
    )
  }

  mutating func releaseTemporaryColor(token: UUID, for identifier: DeviceIdentifier) {
    temporaryColorPreviews[identifier]?[token] = nil
    if temporaryColorPreviews[identifier]?.isEmpty == true {
      temporaryColorPreviews[identifier] = nil
    }
  }

  mutating func setProfileColor(
    _ output: RemappingPhysicalOutput?,
    for identifier: DeviceIdentifier
  ) { profileBaselines[identifier] = output }

  mutating func releaseManualRumble(for identifier: DeviceIdentifier) -> Set<PhysicalOutputChannel>
  {
    let existingChannels = manualClaims[identifier].map { Array($0.keys) } ?? []
    let channels = Set(
      existingChannels.filter {
        if case .rumble = $0 { return true }
        return false
      }
    )
    for channel in channels {
      manualClaims[identifier]?[channel] = nil
      removeEmptyManualStorage(for: identifier, channel: channel)
    }
    return channels
  }

  func effectiveOutput(
    for channel: PhysicalOutputChannel,
    device identifier: DeviceIdentifier
  ) -> RemappingPhysicalOutput? {
    if channel == .color,
      let preview = temporaryColorPreviews[identifier]?.values.max(by: { $0.sequence < $1.sequence }
      )
    {
      return preview.output
    }
    if let manual = manualClaims[identifier]?[channel]?.last?.output,
      channel == .color || !manual.isNeutral
    {
      return manual
    }
    if let mapping = mappingClaims[identifier]?[channel]?.values.max(by: { lhs, rhs in
      lhs.sequence < rhs.sequence
    })?.output {
      return mapping
    }
    return channel == .color ? profileBaselines[identifier] : nil
  }

  /// Mapping claims, colour previews and the profile colour on some channels of one controller, so
  /// a failed mapping or preview write rolls back only what it changed. Manual claims are not part
  /// of it: a failed manual command withdraws its own claim instead.
  struct ChannelState {
    let identifier: DeviceIdentifier
    let clearing: UInt64
    let mappingClaims: [PhysicalOutputChannel: [UUID: Claim]]
    let colorPreviews: [UUID: Claim]?
    let profileBaseline: RemappingPhysicalOutput?
    let channels: Set<PhysicalOutputChannel>
  }

  func state(
    of channels: Set<PhysicalOutputChannel>,
    for identifier: DeviceIdentifier
  ) -> ChannelState {
    ChannelState(
      identifier: identifier,
      clearing: clearing(of: identifier),
      mappingClaims: (mappingClaims[identifier] ?? [:]).filter { channels.contains($0.key) },
      colorPreviews: temporaryColorPreviews[identifier],
      profileBaseline: profileBaselines[identifier],
      channels: channels
    )
  }

  /// Restores `state` unless the controller's claims were cleared since it was captured.
  mutating func restore(_ state: ChannelState) {
    let identifier = state.identifier
    guard clearing(of: identifier) == state.clearing else { return }
    for channel in state.channels {
      mappingClaims[identifier, default: [:]][channel] = state.mappingClaims[channel]
      removeEmptyMappingStorage(for: identifier, channel: channel)
    }
    if state.channels.contains(.color) {
      temporaryColorPreviews[identifier] = state.colorPreviews
      profileBaselines[identifier] = state.profileBaseline
    }
  }

  mutating func removeDevice(_ identifier: DeviceIdentifier) {
    deviceClearings[identifier, default: 0] &+= 1
    mappingClaims[identifier] = nil
    manualClaims[identifier] = nil
    temporaryColorPreviews[identifier] = nil
    profileBaselines[identifier] = nil
  }

  mutating func removeAll() {
    allClearings &+= 1
    mappingClaims.removeAll()
    manualClaims.removeAll()
    temporaryColorPreviews.removeAll()
    profileBaselines.removeAll()
  }

  private func clearing(of identifier: DeviceIdentifier) -> UInt64 {
    (deviceClearings[identifier] ?? 0) &+ allClearings
  }

  private mutating func removeEmptyMappingStorage(
    for identifier: DeviceIdentifier,
    channel: PhysicalOutputChannel
  ) {
    if mappingClaims[identifier]?[channel]?.isEmpty == true {
      mappingClaims[identifier]?[channel] = nil
    }
    if mappingClaims[identifier]?.isEmpty == true { mappingClaims[identifier] = nil }
  }

  private mutating func removeEmptyManualStorage(
    for identifier: DeviceIdentifier,
    channel: PhysicalOutputChannel
  ) {
    if manualClaims[identifier]?[channel]?.isEmpty == true {
      manualClaims[identifier]?[channel] = nil
    }
    if manualClaims[identifier]?.isEmpty == true { manualClaims[identifier] = nil }
  }
}
