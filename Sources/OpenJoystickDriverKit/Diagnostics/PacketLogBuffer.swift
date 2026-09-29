import Foundation

/// Bounded raw packet ring that defers expensive hexadecimal formatting until read.
///
/// Capture is opt-in: packets are recorded only while a diagnostic reader holds a capture lease,
/// which each ``armCapture()`` renews. Once the lease lapses, recording stops and an expiry timer
/// discards what was captured, so no input history outlives the diagnostic session.
/// The input path stores only timestamp, direction, and raw bytes; hex formatting waits for a read.
final class PacketLogBuffer: Sendable {
  private struct BufferedPacket: Sendable {
    let timestamp: TimeInterval
    let direction: PacketLogDirection
    let bytes: [UInt8]
  }

  private struct Ring: Sendable {
    var bufferedPackets: [BufferedPacket?]
    var nextWriteIndex = 0
    var entryCount = 0
    var captureDeadline: UInt64 = 0
    var expiryScheduled = false

    mutating func clear() {
      for index in bufferedPackets.indices { bufferedPackets[index] = nil }
      nextWriteIndex = 0
      entryCount = 0
    }
  }

  private let maxEntries: Int
  private let captureLeaseNanoseconds: UInt64
  private let uptimeNanoseconds: @Sendable () -> UInt64
  // Guards the bounded raw entry array and the lease. Formatting uses a copied snapshot.
  private let ring: Locked<Ring>

  init(
    maxEntries: Int,
    captureLeaseNanoseconds: UInt64 = 5_000_000_000,
    uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) {
    self.maxEntries = max(0, maxEntries)
    self.captureLeaseNanoseconds = captureLeaseNanoseconds
    self.uptimeNanoseconds = uptimeNanoseconds
    self.ring = Locked(Ring(bufferedPackets: Array(repeating: nil, count: self.maxEntries)))
  }

  /// Starts or extends capture for one lease period. A lapsed lease starts from an empty ring.
  func armCapture() {
    let now = uptimeNanoseconds()
    let schedule = ring.withLock { ring in
      if now >= ring.captureDeadline { ring.clear() }
      ring.captureDeadline = now + captureLeaseNanoseconds
      defer { ring.expiryScheduled = true }
      return !ring.expiryScheduled
    }
    if schedule { scheduleExpiry(afterNanoseconds: captureLeaseNanoseconds) }
  }

  /// Discards captured packets once the lease has lapsed; otherwise checks again at its deadline.
  func expireIfLapsed() {
    let now = uptimeNanoseconds()
    let remaining: UInt64? = ring.withLock { ring in
      guard now < ring.captureDeadline else {
        ring.clear()
        ring.expiryScheduled = false
        return nil
      }
      return ring.captureDeadline - now
    }
    if let remaining { scheduleExpiry(afterNanoseconds: remaining) }
  }

  private func scheduleExpiry(afterNanoseconds delay: UInt64) {
    // A floor keeps a renewed lease from rescheduling in a tight loop near its deadline.
    let nanoseconds = Int(clamping: max(delay, 100_000_000))
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(nanoseconds)) {
      [weak self] in self?.expireIfLapsed()
    }
  }

  func append(
    bytes: [UInt8],
    direction: PacketLogDirection,
    timestamp: TimeInterval = Date().timeIntervalSince1970
  ) {
    guard maxEntries > 0 else { return }
    let now = uptimeNanoseconds()
    ring.withLock { ring in
      guard now < ring.captureDeadline else {
        if ring.entryCount > 0 { ring.clear() }
        return
      }
      ring.bufferedPackets[ring.nextWriteIndex] = BufferedPacket(
        timestamp: timestamp,
        direction: direction,
        bytes: bytes
      )
      ring.nextWriteIndex = (ring.nextWriteIndex + 1) % maxEntries
      ring.entryCount = min(ring.entryCount + 1, maxEntries)
    }
  }

  func entries() -> [PacketLogEntry] {
    let snapshot: [BufferedPacket] = ring.withLock { ring in
      guard ring.entryCount > 0 else { return [] }
      let oldestIndex = ring.entryCount == maxEntries ? ring.nextWriteIndex : 0
      return (0..<ring.entryCount).compactMap {
        ring.bufferedPackets[(oldestIndex + $0) % maxEntries]
      }
    }
    return snapshot.map {
      PacketLogEntry(
        timestamp: $0.timestamp,
        direction: $0.direction,
        hex: Self.hexString(for: $0.bytes),
        length: $0.bytes.count
      )
    }
  }

  private static func hexString(for bytes: [UInt8]) -> String {
    guard !bytes.isEmpty else { return "" }

    let digits = Array("0123456789ABCDEF".utf8)
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count * 3 - 1)
    for (index, byte) in bytes.enumerated() {
      if index > 0 { output.append(0x20) }
      output.append(digits[Int(byte >> 4)])
      output.append(digits[Int(byte & 0x0F)])
    }
    return String(bytes: output, encoding: .utf8) ?? ""
  }
}
