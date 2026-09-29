@testable import OpenJoystickDriverUSB

final class SpySource: PassiveUSBRegistrySource, @unchecked Sendable {
  struct Call: Equatable {
    let className: String
    let properties: [String: UInt64]
  }

  var matches: [PassiveUSBRegistryNode]
  var error: PassiveUSBDescriptorProbeError?
  var calls: [Call] = []

  init(matches: [PassiveUSBRegistryNode] = [], error: PassiveUSBDescriptorProbeError? = nil) {
    self.matches = matches
    self.error = error
  }

  func matchingServices(
    className: String,
    numericProperties: [String: UInt64]
  ) throws -> [PassiveUSBRegistryNode] {
    calls.append(Call(className: className, properties: numericProperties))
    if let error { throw error }
    return matches
  }
}
