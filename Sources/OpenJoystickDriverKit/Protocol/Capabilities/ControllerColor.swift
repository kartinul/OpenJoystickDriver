/// An 8-bit-per-channel RGB colour for a controller lightbar or LED, shared by output commands
/// and remapping profiles. It encodes as `{"red", "green", "blue"}` and rejects unknown keys.
public struct ControllerColor: Codable, Hashable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case red
    case green
    case blue
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    red = try values.decode(UInt8.self, forKey: .red)
    green = try values.decode(UInt8.self, forKey: .green)
    blue = try values.decode(UInt8.self, forKey: .blue)
  }
}
