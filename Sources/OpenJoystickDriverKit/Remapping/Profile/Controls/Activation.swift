import Foundation

/// Alternate action fired when a button is held beyond a duration threshold.
public struct RemappingLongHold: Codable, Equatable, Hashable, Sendable {
  public static let durationRange = 100.0...5000.0

  /// Threshold in milliseconds (100...5000).
  public let durationMs: Double
  public let destination: RemappingDestination

  public init(durationMs: Double, destination: RemappingDestination) {
    self.durationMs = durationMs
    self.destination = destination
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case durationMs
    case destination
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    durationMs = try values.decode(Double.self, forKey: .durationMs)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
  }
}

/// Alternate action fired when a button is pressed twice within a time window.
public struct RemappingDoubleTap: Codable, Equatable, Hashable, Sendable {
  public static let windowRange = 50.0...1000.0

  /// Double-tap window in milliseconds (50...1000).
  public let windowMs: Double
  public let destination: RemappingDestination

  public init(windowMs: Double, destination: RemappingDestination) {
    self.windowMs = windowMs
    self.destination = destination
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case windowMs
    case destination
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    windowMs = try values.decode(Double.self, forKey: .windowMs)
    destination = try values.decode(RemappingDestination.self, forKey: .destination)
  }
}
