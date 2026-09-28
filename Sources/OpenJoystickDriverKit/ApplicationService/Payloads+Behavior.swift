import Foundation

extension ApplicationServiceDeviceDescription {

  enum CodingKeys: String, CodingKey {
    case name
    case runtimeIdentifier
    case vendorID
    case productID
    case protocolBinding
    case connection
    case interfaceNumber
    case discoverySource
    case physicalOwnership
    case hidInputOwnership
    case duplicateExposureRisk
    case serialNumber
    case quirks
    case inputEndpoint
    case outputEndpoint
    case needsSetConfiguration
    case postHandshakeSettleMs
    case preferredBackends
    case physicalOutputCapabilities
    case capabilities
    case connectionState
    case sessionState
    case startupCommandStatus
    case inputHealth
    case virtualHIDProfile
  }
}
