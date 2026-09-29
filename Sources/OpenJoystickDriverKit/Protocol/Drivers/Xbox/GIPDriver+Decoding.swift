extension GIPDriver {
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// Share presence varies by model, so only a row with the `share-offset` quirk, whose fixed
  /// offset is the per-record evidence that the model has Share, declares it.
  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: ControlID.xboxLayout.union(usesShareOffset ? [.guide, .share] : [.guide])
    )
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    allowsPhysicalOutput
      ? PhysicalControllerOutputCapabilities(rumbleMotors: [
        .leftMain, .rightMain, .leftTrigger, .rightTrigger,
      ]) : .none
  }

  public var defaultColor: ControllerColor? { nil }

  // MARK: - Frame builders and report decoders

  /// Builds the ACK frame required by a GIP packet with the acknowledge option bit set.
  static func acknowledgementPacket(
    command: UInt8,
    options: UInt8,
    sequence: UInt8,
    totalLength: UInt16,
    remaining: UInt16 = 0
  ) -> [UInt8] {
    let clientAndInternal = (options & 0x0F) | GIPOption.internal
    return [
      GIPCommand.acknowledge, clientAndInternal, sequence, 9, 0, command, clientAndInternal,
      UInt8(truncatingIfNeeded: totalLength), UInt8(truncatingIfNeeded: totalLength >> 8), 0, 0,
      UInt8(truncatingIfNeeded: remaining), UInt8(truncatingIfNeeded: remaining >> 8),
    ]
  }

  func parseLT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[2]) | (UInt16(bytes[3]) << 8) }

  func parseRT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[4]) | (UInt16(bytes[5]) << 8) }

  func parseSticks(from bytes: [UInt8]) -> (Int16, Int16, Int16, Int16) {
    let lsx = Int16(bitPattern: UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[8]) | (UInt16(bytes[9]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
    return (lsx, lsy, rsx, rsy)
  }

  func mapDpad(_ value: UInt8) -> HatDirection {
    // bits: up=1, down=2, left=4, right=8
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast  // up + right
    case 5: .northWest  // up + left
    case 10: .southEast  // down + right
    case 6: .southWest  // down + left
    default: .neutral
    }
  }
}
