import Foundation

/// Transfer direction of a logged packet; raw values are the packet-log wire strings.
public enum PacketLogDirection: String, Codable, Sendable {
  /// Incoming from the controller.
  case received = "rx"
  /// Outgoing to the controller.
  case transmitted = "tx"
}

public enum PacketLogClassification: Sendable, Equatable {
  case activity
  case gipHousekeeping
}

/// One recorded USB packet shown in the Developer tab packet log.
///
/// Stored in a ring buffer inside ``DevicePipeline`` (up to 200 entries).
public struct PacketLogEntry: Codable, Sendable {
  /// Seconds since reference date when the packet was captured.
  public let timestamp: TimeInterval
  /// Transfer direction of the packet.
  public let direction: PacketLogDirection
  /// Packet payload as a hex-encoded string (e.g. `"05 20 00 01 00"`).
  public let hex: String
  /// Number of bytes in the packet.
  public let length: Int

  /// Classifies demonstrated GIP announce and status commands as routine housekeeping.
  public var classification: PacketLogClassification {
    var command: UInt8 = 0
    var digits = 0
    for byte in hex.utf8 {
      if byte == 0x20 || byte == 0x09 { break }
      let digit: UInt8
      switch byte {
      case 48...57: digit = byte - 48
      case 65...70: digit = byte - 55
      case 97...102: digit = byte - 87
      default: return .activity
      }
      guard digits < 2 else { return .activity }
      command = command << 4 | digit
      digits += 1
    }
    guard digits == 2 else { return .activity }
    return command == 0x02 || command == 0x03 ? .gipHousekeeping : .activity
  }
}

/// Tracks newly appended entries across snapshots of a bounded packet ring.
public struct PacketLogSnapshotCursor: Sendable {
  private var previous: [PacketLogEntry]

  public init(snapshot: [PacketLogEntry] = []) { previous = snapshot }

  public mutating func consume(snapshot: [PacketLogEntry]) -> [PacketLogEntry] {
    let overlap = Self.overlap(previous: previous, snapshot: snapshot)
    previous = snapshot
    return Array(snapshot.dropFirst(overlap))
  }

  private static func matches(_ pair: (PacketLogEntry, PacketLogEntry)) -> Bool {
    pair.0.timestamp == pair.1.timestamp && pair.0.direction == pair.1.direction
      && pair.0.length == pair.1.length && pair.0.hex == pair.1.hex
  }

  private static func overlap(previous: [PacketLogEntry], snapshot: [PacketLogEntry]) -> Int {
    var sequence = snapshot.map(Optional.some)
    sequence.append(nil)
    sequence.append(contentsOf: previous.map(Optional.some))
    guard !sequence.isEmpty else { return 0 }
    var prefix = Array(repeating: 0, count: sequence.count)
    for index in 1..<sequence.count {
      var candidate = prefix[index - 1]
      while candidate > 0, !matches(sequence[candidate], sequence[index]) {
        candidate = prefix[candidate - 1]
      }
      if matches(sequence[candidate], sequence[index]) { candidate += 1 }
      prefix[index] = candidate
    }
    return min(prefix[sequence.count - 1], snapshot.count)
  }

  private static func matches(_ lhs: PacketLogEntry?, _ rhs: PacketLogEntry?) -> Bool {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)): return matches((lhs, rhs))
    case (.none, .none): return true
    default: return false
    }
  }
}
