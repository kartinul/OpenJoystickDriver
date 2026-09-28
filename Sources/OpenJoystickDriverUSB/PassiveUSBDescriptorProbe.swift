import Foundation
import IOKit
import OpenJoystickDriverKit

public struct PassiveUSBDescriptorTuple: Equatable, Sendable, Codable, Hashable {
  public let vendorID: UInt16
  public let productID: UInt16

  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }
}

public enum PassiveUSBVerificationState: String, Equatable, Sendable, Codable {
  case observed
  case unverified
}

public enum PassiveUSBDescriptorProbeError: Error, Equatable, Sendable, LocalizedError {
  case contributorGateRequired
  case tupleNotAuthorized
  case matchingFailed(Int32)
  case zeroMatches
  case multipleMatches

  public var errorDescription: String? {
    switch self {
    case .contributorGateRequired: return "contributor gate required"
    case .tupleNotAuthorized: return "VID/PID tuple is not in the passive descriptor allowlist"
    case .matchingFailed(let code): return "IOKit matching failed with return code \(code)"
    case .zeroMatches: return "passive exact-tuple scan found zero devices"
    case .multipleMatches: return "passive exact-tuple scan found multiple devices"
    }
  }
}

public struct PassiveUSBEndpointFacts: Equatable, Sendable, Codable {
  public let address: UInt8
  public let direction: String
  public let transferType: String
  public let maxPacketSize: UInt16
  public let interval: UInt8
  public let superSpeedCompanion: PassiveUSBSuperSpeedCompanion?

  public init(
    address: UInt8,
    direction: String,
    transferType: String,
    maxPacketSize: UInt16,
    interval: UInt8,
    superSpeedCompanion: PassiveUSBSuperSpeedCompanion? = nil
  ) {
    self.address = address
    self.direction = direction
    self.transferType = transferType
    self.maxPacketSize = maxPacketSize
    self.interval = interval
    self.superSpeedCompanion = superSpeedCompanion
  }
}

public struct PassiveUSBInterfaceFacts: Equatable, Sendable, Codable {
  public let number: UInt8
  public let alternateSetting: UInt8
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8
  public let interfaceProtocol: UInt8
  public let declaredEndpointCount: UInt8
  public let endpointState: PassiveUSBVerificationState
  public let endpoints: [PassiveUSBEndpointFacts]

  public init(
    number: UInt8,
    alternateSetting: UInt8,
    interfaceClass: UInt8,
    interfaceSubclass: UInt8,
    interfaceProtocol: UInt8,
    endpointState: PassiveUSBVerificationState,
    declaredEndpointCount: UInt8 = 0,
    endpoints: [PassiveUSBEndpointFacts]
  ) {
    self.number = number
    self.alternateSetting = alternateSetting
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
    self.declaredEndpointCount = declaredEndpointCount
    self.endpointState = endpointState
    self.endpoints = endpoints
  }
}

public struct PassiveUSBRegistryNode: Equatable, Sendable {
  public enum Value: Equatable, Sendable {
    case unsignedInteger(UInt64)
    case string(String)
    case bytes([UInt8])
  }

  public let serviceClass: String
  public let properties: [String: Value]
  public let children: [Self]
  public let registryPath: String
  let registryEntryID: UInt64?

  public init(
    serviceClass: String,
    properties: [String: Value],
    children: [Self] = [],
    registryPath: String = ""
  ) {
    self.init(
      serviceClass: serviceClass,
      properties: properties,
      children: children,
      registryPath: registryPath,
      registryEntryID: nil
    )
  }

  init(
    serviceClass: String,
    properties: [String: Value],
    children: [Self] = [],
    registryPath: String = "",
    registryEntryID: UInt64?
  ) {
    self.serviceClass = serviceClass
    self.properties = properties
    self.children = children
    self.registryPath = registryPath
    self.registryEntryID = registryEntryID
  }
}

public struct PassiveUSBDescriptorBlobSource: Equatable, Sendable, Codable {
  public let propertyKey: String
  public let serviceClass: String
  public let registryPath: String
  public let byteCount: Int

  public init(propertyKey: String, serviceClass: String, registryPath: String, byteCount: Int) {
    self.propertyKey = propertyKey
    self.serviceClass = serviceClass
    self.registryPath = registryPath
    self.byteCount = byteCount
  }
}

public struct PassiveUSBDescriptorBlobAvailability: Equatable, Sendable, Codable {
  public let state: PassiveUSBVerificationState
  public let reason: String
  public let source: PassiveUSBDescriptorBlobSource?

  public init(
    state: PassiveUSBVerificationState,
    reason: String,
    source: PassiveUSBDescriptorBlobSource? = nil
  ) {
    self.state = state
    self.reason = reason
    self.source = source
  }
}

public enum PassiveUSBDescriptorBlobError: Error, Equatable, Sendable {
  case unsafeSize
  case truncated
  case zeroLength
  case descriptorOverrun
  case totalLengthMismatch
  case missingConfiguration
  case duplicateInterfaceOwnership
  case impossibleEndpointOwnership
  case ambiguousDescriptorProperties
  case invalidEndpointAddress
  case invalidTransferAttributes
  case invalidInterval
  case invalidCompanionDescriptor
  case orphanCompanionDescriptor
}

public struct PassiveUSBParsedDescriptor: Equatable, Sendable, Codable {
  public let type: UInt8
  public let bytes: [UInt8]
}

public struct PassiveUSBDescriptorEndpoint: Equatable, Sendable, Codable {
  public let address: UInt8
  public let transferType: String
  public let maxPacketSize: UInt16
  public let interval: UInt8
  public let nominalIntervalMicroseconds: UInt64?
  public let intervalResult: PassiveUSBIntervalResult
  public let superSpeedCompanion: PassiveUSBSuperSpeedCompanion?
  public let superSpeedPlusCompanion: PassiveUSBSuperSpeedPlusCompanion?
}

public enum PassiveUSBIntervalResult: Equatable, Sendable, Codable {
  case unsupportedSpeedOrTransfer
  case ignoredNotServiceInterval
  case validDescriptorNominal(UInt64)
  case invalidRange
}

public struct PassiveUSBSuperSpeedCompanion: Equatable, Sendable, Codable {
  public let maxBurst: UInt8
  public let attributes: UInt8
  public let bytesPerInterval: UInt16
}

public struct PassiveUSBSuperSpeedPlusCompanion: Equatable, Sendable, Codable {
  public let bytesPerInterval: UInt32
}

public struct PassiveUSBSuperSpeedPlusValidationContext: Equatable, Sendable, Codable {
  public let maxIsoBytesPerBiGen1: UInt32
  public let numberOfLanes: UInt32
  public let laneSpeedMantissa: UInt32
  public let laneSpeedMantissaGen1: UInt32

  public init(
    maxIsoBytesPerBiGen1: UInt32,
    numberOfLanes: UInt32,
    laneSpeedMantissa: UInt32,
    laneSpeedMantissaGen1: UInt32
  ) {
    self.maxIsoBytesPerBiGen1 = maxIsoBytesPerBiGen1
    self.numberOfLanes = numberOfLanes
    self.laneSpeedMantissa = laneSpeedMantissa
    self.laneSpeedMantissaGen1 = laneSpeedMantissaGen1
  }

  public var maximumBytesPerInterval: UInt32? {
    guard numberOfLanes > 0, laneSpeedMantissaGen1 > 0 else { return nil }
    let product = UInt64(maxIsoBytesPerBiGen1).multipliedReportingOverflow(
      by: UInt64(numberOfLanes)
    )
    guard !product.overflow else { return nil }
    let scaled = product.partialValue.multipliedReportingOverflow(by: UInt64(laneSpeedMantissa))
    guard !scaled.overflow else { return nil }
    let value = scaled.partialValue / UInt64(laneSpeedMantissaGen1)
    return value <= UInt64(UInt32.max) ? UInt32(value) : nil
  }
}

public struct PassiveUSBDescriptorInterface: Equatable, Sendable, Codable {
  public let number: UInt8
  public let alternateSetting: UInt8
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8
  public let interfaceProtocol: UInt8
  public let declaredEndpointCount: UInt8
  public let endpoints: [PassiveUSBDescriptorEndpoint]
}

public enum PassiveUSBNegotiatedSpeed: String, Equatable, Sendable, Codable {
  case low
  case full
  case high
  case superSpeed
  case superSpeedPlus
}

public struct PassiveUSBConfigurationDescriptor: Equatable, Sendable, Codable {
  public let totalLength: UInt16
  public let declaredInterfaceCount: UInt8
  public let descriptors: [PassiveUSBParsedDescriptor]
  public let interfaces: [PassiveUSBDescriptorInterface]
  public let negotiatedSpeed: PassiveUSBNegotiatedSpeed?
}

public enum PassiveUSBSpeedObservationState: String, Equatable, Sendable, Codable {
  case absent
  case observed
  case ambiguous
}

public struct PassiveUSBSpeedObservation: Equatable, Sendable, Codable {
  public let state: PassiveUSBSpeedObservationState
  public let speed: PassiveUSBNegotiatedSpeed?
  public let sources: [String]
  public let values: [String]
  public let properties: [PassiveUSBSpeedPropertyObservation]
}

public struct PassiveUSBSpeedPropertyObservation: Equatable, Sendable, Codable {
  public let key: String
  public let rawType: String
  public let rawValue: String
  public let decodedSpeed: PassiveUSBNegotiatedSpeed?
}
