@testable import OpenJoystickDriverKit

extension ProtocolBindingResult {
  /// A `hid.descriptor` binding with no observed interfaces, for descriptions whose binding
  /// decision a test does not examine.
  static let hidDescriptorFixture = ProtocolBindingResult(
    binding: ProtocolBinding(
      protocolID: .hidDescriptor,
      variant: nil,
      accessBackend: .ioHID,
      interfaceNumber: nil,
      rule: .hidDescriptor,
      matchedPredicates: [.hidDescriptorContract],
      record: nil
    ),
    interfaces: []
  )
}
