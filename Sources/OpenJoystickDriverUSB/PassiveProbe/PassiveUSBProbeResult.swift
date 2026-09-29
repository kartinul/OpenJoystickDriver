import Foundation
import IOKit
import OpenJoystickDriverKit

public struct PassiveUSBObservedUSBFacts: Equatable, Sendable, Codable {
  public let tuple: PassiveUSBDescriptorTuple
  public let name: String?
  /// Raw USB `bcdDevice`; nil when the registry does not expose a 16-bit value.
  public let deviceRelease: UInt16?
  public let deviceClass: UInt8?
  public let deviceSubclass: UInt8?
  public let deviceProtocol: UInt8?
  public let configurationCount: UInt8?
  public let activeConfiguration: UInt8?
  public let interfacesState: PassiveUSBVerificationState
  public let hidDescriptorState: PassiveUSBVerificationState
  public let hidCollectionsState: PassiveUSBVerificationState
  public let hidUsagesState: PassiveUSBVerificationState
  public let serviceBindingsState: PassiveUSBVerificationState
  public let serviceClasses: [String]
  public let descriptorBlobSource: PassiveUSBDescriptorBlobSource?
  public let descriptorBlobSources: [PassiveUSBDescriptorBlobSource]
  public let descriptorBlobAvailability: PassiveUSBDescriptorBlobAvailability
  public let speedObservation: PassiveUSBSpeedObservation
  public let configurationDescriptor: PassiveUSBConfigurationDescriptor?
  public let descriptorParseError: String?
  public let verification: PassiveUSBVerificationFacts
}

public struct PassiveUSBVerificationFacts: Equatable, Sendable, Codable {
  public let endpointState: PassiveUSBVerificationState
  public let hidDescriptorState: PassiveUSBVerificationState
  public let hidCollectionsState: PassiveUSBVerificationState
  public let hidUsagesState: PassiveUSBVerificationState
  public let mappingState: PassiveUSBVerificationState
  public let inputState: PassiveUSBVerificationState
  public let outputState: PassiveUSBVerificationState
  public let reconnectState: PassiveUSBVerificationState
  public let latencyState: PassiveUSBVerificationState
  public let consumerRecognitionState: PassiveUSBVerificationState
  public let supportState: PassiveUSBVerificationState

  public init(
    endpointState: PassiveUSBVerificationState = .unverified,
    hidDescriptorState: PassiveUSBVerificationState = .unverified,
    hidCollectionsState: PassiveUSBVerificationState = .unverified,
    hidUsagesState: PassiveUSBVerificationState = .unverified,
    mappingState: PassiveUSBVerificationState = .unverified,
    inputState: PassiveUSBVerificationState = .unverified,
    outputState: PassiveUSBVerificationState = .unverified,
    reconnectState: PassiveUSBVerificationState = .unverified,
    latencyState: PassiveUSBVerificationState = .unverified,
    consumerRecognitionState: PassiveUSBVerificationState = .unverified,
    supportState: PassiveUSBVerificationState = .unverified
  ) {
    self.endpointState = endpointState
    self.hidDescriptorState = hidDescriptorState
    self.hidCollectionsState = hidCollectionsState
    self.hidUsagesState = hidUsagesState
    self.mappingState = mappingState
    self.inputState = inputState
    self.outputState = outputState
    self.reconnectState = reconnectState
    self.latencyState = latencyState
    self.consumerRecognitionState = consumerRecognitionState
    self.supportState = supportState
  }
}

public struct PassiveUSBCatalogInference: Equatable, Sendable, Codable {
  public let source: String
  public let record: String
  public let parser: String
  public let endpoints: [String: UInt8]
}

public struct PassiveUSBProtocolClassification: Equatable, Sendable, Codable {
  public let status: String
  public let descriptorPredicates: [String]
  public let wireProtocol: String
}

public enum PassiveUSBParsedDescriptorState: String, Equatable, Sendable, Codable {
  case absent
  case parsed
  case ambiguous
  case malformed
}

public struct PassiveUSBParsedDescriptorFacts: Equatable, Sendable, Codable {
  public let state: PassiveUSBParsedDescriptorState
  public let configuration: PassiveUSBConfigurationDescriptor?
  public let sources: [PassiveUSBDescriptorBlobSource]
  public let error: String?
}

public struct PassiveUSBSpecificationInference: Equatable, Sendable, Codable {
  public let sourceIDs: [String]
  public let claims: [String]
}

public struct PassiveUSBUserReportedPolling: Equatable, Sendable, Codable {
  public let state: PassiveUSBVerificationState
  public let reportsPerSecond: Double?
}

public struct PassiveUSBProbeResult: Equatable, Sendable, Codable {
  public let observedUSBFacts: PassiveUSBObservedUSBFacts
  public let parsedDescriptorFacts: PassiveUSBParsedDescriptorFacts
  public let specificationInference: PassiveUSBSpecificationInference
  public let catalogInference: PassiveUSBCatalogInference
  public let protocolClassification: PassiveUSBProtocolClassification
  public let userReportedPolling: PassiveUSBUserReportedPolling
}
