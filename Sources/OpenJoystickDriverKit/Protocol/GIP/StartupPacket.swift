import Foundation

/// Driver-owned GIP initialization actions used by Xbox One-class controllers.
///
/// Raw values are the protocol-scoped action IDs a catalog row selects in
/// `protocol.initialization`; this driver owns the bytes each action sends.
public enum GIPStartupPacket: String, CaseIterable, Sendable {
  case powerOn = "xbox.gip/power-on"
  case xboxOneSInit = "xbox.gip/s-init"
  case extraInput = "xbox.gip/enable-extra-input"
  case horiAck = "xbox.gip/hori-ack"
  case ledOn = "xbox.gip/led-on"
  case authDone = "xbox.gip/auth-done"
  case rumbleBegin = "xbox.gip/rumble-begin"
  case rumbleEnd = "xbox.gip/rumble-end"

  public static let defaultSequence: [Self] = [.powerOn, .ledOn, .authDone]

  /// Host recipes that change packing after handshake. Recipes join this set
  /// only when the exact packet is an operational fact in this parser.
  public var isDiagnosticRecipe: Bool {
    switch self {
    case .powerOn, .xboxOneSInit, .extraInput, .horiAck, .ledOn, .authDone, .rumbleBegin,
      .rumbleEnd:
      false
    }
  }

  public var command: UInt8 {
    switch self {
    case .powerOn, .xboxOneSInit: GIPCommand.power
    case .extraInput: 0x4D
    case .horiAck: GIPCommand.acknowledge
    case .ledOn: GIPCommand.led
    case .authDone: 0x06
    case .rumbleBegin, .rumbleEnd: GIPCommand.rumble
    }
  }

  public func packet(sequence: UInt8) -> [UInt8] {
    switch self {
    case .powerOn: [GIPCommand.power, GIPOption.internal, sequence, 1, 0]
    case .xboxOneSInit: [GIPCommand.power, GIPOption.internal, sequence, 15, 6]
    case .extraInput: [0x4D, 0x10, sequence, 2, GIPCommand.virtualKey, 0]
    case .horiAck:
      [1, GIPOption.internal, sequence, 9, 0, 4, GIPOption.internal, 58, 0, 0, 0, 128, 0]
    case .ledOn: [GIPCommand.led, GIPOption.internal, sequence, 3, 0, 1, 20]
    case .authDone: [6, GIPOption.internal, sequence, 2, 1, 0]
    case .rumbleBegin: [GIPCommand.rumble, 0, sequence, 9, 0, 15, 0, 0, 29, 29, 255, 0, 0]
    case .rumbleEnd: [GIPCommand.rumble, 0, sequence, 9, 0, 15, 0, 0, 0, 0, 0, 0, 0]
    }
  }
}
