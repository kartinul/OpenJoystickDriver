import Foundation

public protocol PassiveUSBRegistrySource: Sendable {
  func matchingServices(
    className: String,
    numericProperties: [String: UInt64]
  ) throws -> [PassiveUSBRegistryNode]
}

public enum PassiveUSBRegistryFactParser {
  public static func parse(
    root: PassiveUSBRegistryNode,
    tuple: PassiveUSBDescriptorTuple,
    catalogInference: PassiveUSBCatalogInference
  ) -> PassiveUSBProbeResult {
    let blobs = findDescriptorBlobs(root)
    let blob = blobs.first
    let ambiguous = blobs.map(\.bytes).contains { $0 != blob?.bytes }
    let speedObservation = observeSpeed(root)
    let negotiatedSpeed = speedObservation.state == .observed ? speedObservation.speed : nil
    let parsed: Result<PassiveUSBConfigurationDescriptor, PassiveUSBDescriptorBlobError>?
    if ambiguous {
      parsed = .failure(.ambiguousDescriptorProperties)
    } else if let blob {
      do {
        parsed = .success(
          try PassiveUSBConfigurationDescriptorParser.parse(
            blob.bytes,
            negotiatedSpeed: negotiatedSpeed
          )
        )
      } catch let error as PassiveUSBDescriptorBlobError { parsed = .failure(error) } catch {
        parsed = .failure(.truncated)
      }
    } else {
      parsed = nil
    }
    let parsedDescriptor: PassiveUSBConfigurationDescriptor?
    let parseError: PassiveUSBDescriptorBlobError?
    switch parsed {
    case .success(let value):
      parsedDescriptor = value
      parseError = nil
    case .failure(let error):
      parsedDescriptor = nil
      parseError = error
    case nil:
      parsedDescriptor = nil
      parseError = nil
    }
    let deviceClass = uint8(root, "bDeviceClass")
    let deviceSubclass = uint8(root, "bDeviceSubClass")
    let deviceProtocol = uint8(root, "bDeviceProtocol")
    let predicates =
      deviceClass == 0xFF && deviceSubclass == 0xFF && deviceProtocol == 0xFF
      ? ["P-DEV-255-255-255"] : []
    let blobSource =
      ambiguous
      ? nil
      : blob.map {
        PassiveUSBDescriptorBlobSource(
          propertyKey: $0.key,
          serviceClass: $0.node.serviceClass,
          registryPath: $0.node.registryPath,
          byteCount: $0.bytes.count
        )
      }
    let observed = PassiveUSBObservedUSBFacts(
      tuple: tuple,
      name: string(root, "USB Product Name") ?? string(root, "Product Name"),
      deviceRelease: uint16(root, "bcdDevice"),
      deviceClass: deviceClass,
      deviceSubclass: deviceSubclass,
      deviceProtocol: deviceProtocol,
      configurationCount: uint8(root, "bNumConfigurations"),
      activeConfiguration: uint8(root, "kUSBCurrentConfiguration"),
      interfacesState: .unverified,
      hidDescriptorState: .unverified,
      hidCollectionsState: .unverified,
      hidUsagesState: .unverified,
      serviceBindingsState: .unverified,
      serviceClasses: [root.serviceClass],
      descriptorBlobSource: blobSource,
      descriptorBlobSources: blobs.map {
        PassiveUSBDescriptorBlobSource(
          propertyKey: $0.key,
          serviceClass: $0.node.serviceClass,
          registryPath: $0.node.registryPath,
          byteCount: $0.bytes.count
        )
      },
      descriptorBlobAvailability: PassiveUSBDescriptorBlobAvailability(
        state: parsedDescriptor == nil ? .unverified : .observed,
        reason: blobs.isEmpty
          ? "no readable descriptor byte property in exact-tuple registry tree"
          : parseError.map { String(describing: $0) } ?? "parsed",
        source: blobSource
      ),
      speedObservation: speedObservation,
      configurationDescriptor: nil,
      descriptorParseError: nil,
      verification: PassiveUSBVerificationFacts(endpointState: .unverified)
    )
    let parsedState: PassiveUSBParsedDescriptorState =
      ambiguous
      ? .ambiguous : parsedDescriptor != nil ? .parsed : blob == nil ? .absent : .malformed
    return PassiveUSBProbeResult(
      observedUSBFacts: observed,
      parsedDescriptorFacts: PassiveUSBParsedDescriptorFacts(
        state: parsedState,
        configuration: parsedDescriptor,
        sources: blobs.map {
          PassiveUSBDescriptorBlobSource(
            propertyKey: $0.key,
            serviceClass: $0.node.serviceClass,
            registryPath: $0.node.registryPath,
            byteCount: $0.bytes.count
          )
        },
        error: parseError.map { String(describing: $0) }
      ),
      specificationInference: PassiveUSBSpecificationInference(
        sourceIDs: ["USB-2.0-9.6.6", "USB-3.2-9.6.6"],
        claims: ["bInterval is descriptor-nominal only"]
      ),
      catalogInference: catalogInference,
      protocolClassification: PassiveUSBProtocolClassification(
        status: predicates.isEmpty ? "UNVERIFIED" : "device-descriptor vendor-specific",
        descriptorPredicates: predicates,
        wireProtocol: "UNVERIFIED"
      ),
      userReportedPolling: PassiveUSBUserReportedPolling(state: .unverified, reportsPerSecond: nil)
    )
  }

  private struct Blob {
    let key: String
    let bytes: [UInt8]
    let node: PassiveUSBRegistryNode
  }

  static let descriptorKeys = [
    "Configuration Descriptor", "kUSBConfigurationDescriptor", "USB Configuration Descriptor",
    "DescriptorBytes", "descriptorBytes",
  ]

  private static func findDescriptorBlobs(_ node: PassiveUSBRegistryNode) -> [Blob] {
    var result: [Blob] = []
    for key in descriptorKeys {
      if case .bytes(let bytes) = node.properties[key] {
        result.append(Blob(key: key, bytes: bytes, node: node))
      }
    }
    for child in node.children { result.append(contentsOf: findDescriptorBlobs(child)) }
    return result
  }

  private static func uint8(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt8? {
    uint64(node, key).flatMap(UInt8.init(exactly:))
  }
  private static func uint16(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt16? {
    uint64(node, key).flatMap(UInt16.init(exactly:))
  }
  private static func uint64(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt64? {
    guard case .unsignedInteger(let value) = node.properties[key] else { return nil }
    return value
  }
  private static func string(_ node: PassiveUSBRegistryNode, _ key: String) -> String? {
    guard case .string(let value) = node.properties[key] else { return nil }
    return value
  }
}
