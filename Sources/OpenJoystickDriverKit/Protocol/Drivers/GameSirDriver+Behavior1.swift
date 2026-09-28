import Foundation

extension GameSirDriver {

  // Share is emitted but not yet declared until per-model evidence confirms it.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      usbKeepAliveIntervalNanoseconds: gameSirProtocol == .g7ProUSB
        ? gameSirHeartbeatIntervalNanoseconds : nil,
      hidStartupIntervalNanoseconds: gameSirCommandIntervalNanoseconds,
      hidKeepAliveIntervalNanoseconds: gameSirHeartbeatIntervalNanoseconds,
      minimumHIDOutputIntervalNanoseconds: gameSirCommandIntervalNanoseconds
    )
  }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    // The wired G7 Pro telemetry always reports the inner grips.
    let innerGrips: Set<ControlID> =
      gameSirProtocol == .g7ProUSB || hasInnerGrips ? [.paddleLeft2, .paddleRight2] : []
    let backButtons = innerGrips.union([.paddleLeft1, .paddleRight1, .auxiliary1])
    // No motion: no source verifies the IMU scale, frame, or byte order.
    return ControllerCapabilities(controls: ControlID.xboxLayout.union([.guide]).union(backButtons))
  }

  public var power: ControllerConnectionState.Power? {
    stateLock.withLock { storedPower }

  }

  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)

    return stateLock.withLock {
      switch gameSirProtocol {
      case .g7ProUSB:
        if bytes.count == 20, bytes.prefix(2) == [0x00, 0x14] {
          sessionReady = true
          guard let standard = standardParser.decode(data) else { return nil }
          state.apply(changesFrom: standardState, to: standard)
          standardState = standard
          return ControllerEvent(timestamp: receivedAt, state: state)
        }
        return parseG7Telemetry(bytes, receivedAt: receivedAt)
      case .enhancedHID: return parseEnhanced(bytes, receivedAt: receivedAt)
      }
    }
  }

  public func resetProtocolState() {
    stateLock.withLock {
      standardParser = XUSBDriver()
      state = .neutral
      standardState = .neutral
      telemetryExtras = .neutral
      sequence = 0
      sessionReady = false
      activeLightingSlot = nil
      lightingBrightness = 100
      storedPower = nil
    }
  }

  public func startupWrites() -> [PhysicalOutputWrite] {
    guard gameSirProtocol == .enhancedHID else { return [] }
    var reports = [Self.hidReport(gameSirEnhancedHIDHeartbeatPayload)]
    if usesLightingSlots { reports.append(Self.hidReport([0x0F, 0x04, 0x20, 0x00, 0x00, 0x01])) }
    return reports.map { .hidOutput($0) }
  }

  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard gameSirProtocol == .g7ProUSB else {
      return [.hidOutput(Self.hidReport(gameSirEnhancedHIDHeartbeatPayload))]
    }
    return stateLock.withLock {
      [
        .usb(
          PhysicalUSBOutputPacket(
            endpoint: outEndpoint,
            bytes: g7Packet(command: 0x02, payload: [0xF2, 0x00]),
            timeoutMilliseconds: gameSirUSBTimeoutMilliseconds
          )
        )
      ]
    }
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    let lighting: [PhysicalLightingFeature] =
      switch gameSirProtocol {
      case .g7ProUSB: [.programmableBrightness]
      case .enhancedHID: [.programmableColor, .programmableBrightness]
      }
    return PhysicalControllerOutputCapabilities(
      rumbleMotors: gameSirProtocol == .enhancedHID ? [.leftMain, .rightMain] : [],
      lightingFeatures: lighting
    )
  }

  public var defaultColor: (red: UInt8, green: UInt8, blue: UInt8)? { (0, 128, 255) }

  /// Colour and brightness wait for the session and, on slot-based models, the active lighting
  /// slot.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      return rumblePlan(left: intensities.leftMain.byte, right: intensities.rightMain.byte)
    case .stopRumble: return rumblePlan(left: 0, right: 0)
    case .setRGB(let red, let green, let blue):
      guard gameSirProtocol == .enhancedHID else {
        throw .unsupportedCapability(command.capability)
      }
      guard let plan = colorPlan(red: red, green: green, blue: blue) else { throw .notReady }
      return plan
    case .setLightBrightness(let brightness):
      guard let plan = brightnessPlan(brightness.byte) else { throw .notReady }
      return plan
    default: throw .unsupportedCapability(command.capability)
    }
  }

  private func rumblePlan(left: UInt8, right: UInt8) -> PhysicalOutputPlan {
    PhysicalOutputPlan(writes: [.hidOutput(Self.hidReport([0x0F, 0x20, 0x66, 0x55, left, right]))])
  }

  /// Nil until the session is ready and, on slot-based models, the active slot is known.
  private func colorPlan(red: UInt8, green: UInt8, blue: UInt8) -> PhysicalOutputPlan? {
    stateLock.withLock {
      guard sessionReady else { return nil }
      if usesLightingSlots {
        guard let slot = activeLightingSlot, slot <= 4 else { return nil }
        let frame = Self.solidColorFrame(red: red, green: green, blue: blue)
        let record: [UInt8] =
          [0x01, 0x05, 0x14, lightingBrightness] + Array(repeating: frame, count: 8).flatMap { $0 }
        var reports = Self.bareWriteReports(
          bank: 0x20,
          address: 0x0001 + UInt16(slot) * 0x007C,
          data: record
        )
        reports += Self.bareWriteReports(bank: 0x20, address: 0x0000, data: [slot])
        return PhysicalOutputPlan(
          writes: reports.map { .hidOutput($0) },
          intervalNanoseconds: gameSirCommandIntervalNanoseconds
        )
      }
      let (hue, saturation) = Self.hueAndSaturation(red: red, green: green, blue: blue)
      let data = [UInt8(hue >> 8), UInt8(hue & 0xFF), saturation]
      let reports = [0x000C, 0x0010, 0x0014, 0x0018].flatMap {
        Self.bareWriteReports(bank: 0x20, address: UInt16($0), data: data)
      }
      return PhysicalOutputPlan(
        writes: reports.map { .hidOutput($0) },
        intervalNanoseconds: gameSirCommandIntervalNanoseconds
      )
    }
  }

  /// Wired G7 Pro brightness goes to the bound USB endpoint; enhanced HID writes lighting memory
  /// and records the value the next colour record carries. Nil, changing nothing, until the
  /// session is ready and, on slot-based models, the active slot is known.
  private func brightnessPlan(_ brightness: UInt8) -> PhysicalOutputPlan? {
    stateLock.withLock {
      guard sessionReady else { return nil }
      let value = UInt8((Double(brightness) * 100 / Double(UInt8.max)).rounded())
      if gameSirProtocol == .g7ProUSB {
        let packet = PhysicalUSBOutputPacket(
          endpoint: outEndpoint,
          bytes: g7Packet(command: 0x3C, payload: [0x03, 0x20, 0x01, 0xF9, 0x01, value]),
          timeoutMilliseconds: gameSirUSBTimeoutMilliseconds
        )
        return PhysicalOutputPlan(writes: [.usb(packet)])
      }
      var address: UInt16 = 0x0001
      if usesLightingSlots {
        guard let slot = activeLightingSlot, slot <= 4 else { return nil }
        address = 0x0001 + UInt16(slot) * 0x007C + 3
      }
      lightingBrightness = value
      return PhysicalOutputPlan(
        writes: Self.bareWriteReports(bank: 0x20, address: address, data: [value]).map {
          .hidOutput($0)
        }
      )
    }
  }

  private func parseG7Telemetry(
    _ bytes: [UInt8],
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard bytes.count == gameSirReportLength, bytes[0] == 0x10 else { return nil }
    if bytes[1] == 0x05, bytes[2] == 0x20, bytes[3] == 0, bytes[4] == 0, bytes[5] == 1,
      bytes[6] <= 4
    {
      activeLightingSlot = bytes[6]
      return nil
    }
    guard bytes[3] == 0x3C, bytes[4] == 0xE0 else { return nil }
    sessionReady = true
    updateBattery(percentage: bytes[33], charging: bytes[32] == 1)
    var extras = telemetryExtras
    setExtraButtons(bytes[60], includesInnerGrips: true, in: &extras)
    state.apply(changesFrom: telemetryExtras, to: extras)
    telemetryExtras = extras
    return ControllerEvent(timestamp: receivedAt, state: state)
  }

  private func parseEnhanced(_ bytes: [UInt8], receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    guard bytes.count == gameSirReportLength else { return nil }
    if bytes[0] == 0x10, bytes[1] == 0x05, bytes[2] == 0x20, bytes[3] == 0, bytes[4] == 0,
      bytes[5] == 1, bytes[6] <= 4, usesLightingSlots
    {
      activeLightingSlot = bytes[6]
      return nil
    }
    guard bytes[0] == 0x12 else { return nil }
    sessionReady = true
    updateBattery(percentage: bytes[36], charging: bytes[35] & 1 != 0)
    var next = state
    let face = bytes[5]
    let meta = bytes[6]
    for (byte, mask, control) in [
      (face, 0x10, ControlID.faceWest), (face, 0x20, .faceSouth), (face, 0x40, .faceEast),
      (face, 0x80, .faceNorth), (meta, 0x01, .leftShoulder), (meta, 0x02, .rightShoulder),
      (meta, 0x10, .view), (meta, 0x20, .menu), (meta, 0x40, .leftStickClick),
      (meta, 0x80, .rightStickClick),
    ] as [(UInt8, UInt8, ControlID)] { next.set(control, pressed: byte & mask != 0) }
    next.hat = Self.dpadDirection(face & 0x0F)
    next.leftStick = StickPosition(x: Self.axis(bytes[1]), yDown: -Self.axis(bytes[2]))
    next.rightStick = StickPosition(x: Self.axis(bytes[3]), yDown: -Self.axis(bytes[4]))
    next.leftTrigger = UnipolarValue(normalized: Float(bytes[8]) / 255)
    next.rightTrigger = UnipolarValue(normalized: Float(bytes[9]) / 255)
    setExtraButtons(bytes[60], includesInnerGrips: hasInnerGrips, in: &next)
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// GameSir reports an exact percentage; charging implies wired power, its absence says nothing.
  private func updateBattery(percentage: UInt8, charging: Bool) {
    let exact = min(percentage, 100)
    storedPower = ControllerConnectionState.Power(
      charging: charging ? .charging : .discharging,
      battery: BatteryLevel(percentage: exact...exact),
      wiredPower: charging ? true : nil
    )
  }

  private func setExtraButtons(
    _ value: UInt8,
    includesInnerGrips: Bool,
    in state: inout ControllerState
  ) {
    var table: [(UInt8, ControlID)] = [
      (0x01, .guide), (0x02, .share), (0x08, .paddleLeft1), (0x10, .paddleRight1),
      (0x20, .auxiliary1),
    ]
    if includesInnerGrips { table += [(0x40, .paddleLeft2), (0x80, .paddleRight2)] }
    for (mask, control) in table { state.set(control, pressed: value & mask != 0) }
  }

  private func g7Packet(command: UInt8, payload: [UInt8]) -> [UInt8] {
    sequence &+= 1
    return Self.padded([0x0F, 0x00, sequence, command] + payload)
  }

  private static func hidReport(_ bytes: [UInt8]) -> PhysicalHIDOutputReport {
    PhysicalHIDOutputReport(reportID: 0x0F, bytes: padded(bytes))
  }

  private static func bareWriteReports(
    bank: UInt8,
    address: UInt16,
    data: [UInt8]
  ) -> [PhysicalHIDOutputReport] {
    stride(from: 0, to: data.count, by: 48).map { offset in
      let chunk = Array(data[offset..<min(data.count, offset + 48)])
      let currentAddress = address + UInt16(offset)
      return hidReport(
        [
          0x0F, 0x03, bank, UInt8(currentAddress >> 8), UInt8(currentAddress & 0xFF),
          UInt8(chunk.count),
        ] + chunk
      )
    }
  }

  private static func padded(_ bytes: [UInt8]) -> [UInt8] {
    Array((bytes + Array(repeating: 0, count: gameSirReportLength)).prefix(gameSirReportLength))
  }
}

extension ControllerState {
  /// Applies every field that differs between `old` and `new`: the controls one report stream
  /// changed since its own last decode.
  mutating func apply(changesFrom old: ControllerState, to new: ControllerState) {
    for control in old.pressed.symmetricDifference(new.pressed) {
      set(control, pressed: new.pressed.contains(control))
    }
    if old.hat != new.hat { hat = new.hat }
    if old.leftStick != new.leftStick { leftStick = new.leftStick }
    if old.rightStick != new.rightStick { rightStick = new.rightStick }
    if old.leftTrigger != new.leftTrigger { leftTrigger = new.leftTrigger }
    if old.rightTrigger != new.rightTrigger { rightTrigger = new.rightTrigger }
  }
}
