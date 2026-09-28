import Foundation

let gameSirReportLength = 64
let gameSirHeartbeatIntervalNanoseconds: UInt64 = 500_000_000
let gameSirCommandIntervalNanoseconds: UInt64 = 20_000_000
let gameSirUSBTimeoutMilliseconds: UInt32 = 2_000
let gameSirEnhancedHIDHeartbeatPayload: [UInt8] = [0x0F, 0xF2]

/// GameSir protocol families backed by the vendor's observed report streams.
public enum GameSirProtocol: Sendable, Equatable {
  case g7ProUSB
  case enhancedHID
}

/// Driver for source-backed GameSir controller identities.
public final class GameSirDriver: PhysicalProtocolDriver {
  let gameSirProtocol: GameSirProtocol
  /// Enhanced HID extras report the inner grips (catalog quirk `inner-grips`).
  let hasInnerGrips: Bool
  /// Enhanced HID lighting memory is slot-based (catalog quirk `lighting-slots`).
  let usesLightingSlots: Bool
  let outEndpoint: UInt8
  let stateLock = NSLock()
  var standardParser = XUSBDriver()
  var state = ControllerState.neutral
  /// The wired G7 splits input over two streams, standard XUSB reports and telemetry; each applies
  /// only the controls it changed, measured against its own last decode.
  var standardState = ControllerState.neutral
  var telemetryExtras = ControllerState.neutral
  var sequence: UInt8 = 0
  var sessionReady = false
  var activeLightingSlot: UInt8?
  var lightingBrightness: UInt8 = 100
  var storedPower: ControllerConnectionState.Power?

  /// - Parameter outEndpoint: Interrupt OUT endpoint of the bound USB interface, for keep-alive
  ///   and brightness.
  public init(
    protocol gameSirProtocol: GameSirProtocol,
    hasInnerGrips: Bool = false,
    usesLightingSlots: Bool = false,
    outEndpoint: UInt8 = 0x02
  ) {
    self.gameSirProtocol = gameSirProtocol
    self.hasInnerGrips = hasInnerGrips
    self.usesLightingSlots = usesLightingSlots
    self.outEndpoint = outEndpoint
  }
}
