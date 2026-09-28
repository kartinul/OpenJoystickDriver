import Foundation

extension GameSirDriver {

  static func axis(_ value: UInt8) -> Float {
    let centered = Float(Int(value) - 128)
    return max(-1, min(1, centered / (centered < 0 ? 128 : 127)))
  }

  static func dpadDirection(_ value: UInt8) -> HatDirection {
    switch value {
    case 0: .north
    case 1: .northEast
    case 2: .east
    case 3: .southEast
    case 4: .south
    case 5: .southWest
    case 6: .west
    case 7: .northWest
    default: .neutral
    }
  }

  static func hueAndSaturation(red: UInt8, green: UInt8, blue: UInt8) -> (UInt16, UInt8) {
    let r = Double(red) / 255
    let g = Double(green) / 255
    let b = Double(blue) / 255
    let maximum = max(r, g, b)
    let minimum = min(r, g, b)
    let delta = maximum - minimum
    let saturation = maximum == 0 ? 0 : UInt8((delta / maximum * 100).rounded())
    guard delta > 0 else { return (0, saturation) }
    let rawHue: Double
    if maximum == r {
      rawHue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == g {
      rawHue = 60 * ((b - r) / delta + 2)
    } else {
      rawHue = 60 * ((r - g) / delta + 4)
    }
    return (UInt16((rawHue < 0 ? rawHue + 360 : rawHue).rounded()) % 360, saturation)
  }

  static func solidColorFrame(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
    stride(from: 0, to: 15, by: 3).reduce(into: [UInt8](repeating: 0, count: 15)) {
      result,
      offset in
      result[offset] = red
      result[offset + 1] = green
      result[offset + 2] = blue
    }
  }
}
