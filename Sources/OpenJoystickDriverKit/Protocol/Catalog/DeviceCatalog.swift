import Foundation

/// Loads the canonical VID/PID controller records bundled with the driver.
struct DeviceCatalog: Sendable {
  private let profiles: [String: DeviceRuntimeProfile]
  let rawUSBProfileIdentifiers: [DeviceIdentifier]
  let hidProfileIdentifiers: [DeviceIdentifier]

  init() {
    do {
      var loaded: [String: DeviceRuntimeProfile] = [:]
      var hid: [DeviceIdentifier] = []
      var rawUSB: [DeviceIdentifier] = []
      for record in try Self.loadRecords() {
        let key = "\(record.vendorID):\(record.productID)"
        guard loaded[key] == nil else { throw CatalogError("duplicate controller identity \(key)") }
        let profile = try Self.makeRuntimeProfile(record)
        loaded[key] = profile
        let identifier = DeviceIdentifier(
          vendorID: UInt16(record.vendorID),
          productID: UInt16(record.productID)
        )
        if profile.usesRawUSB { rawUSB.append(identifier) } else { hid.append(identifier) }
      }
      profiles = loaded
      let modelOrder: (DeviceIdentifier, DeviceIdentifier) -> Bool = {
        ($0.controllerIdentity.vendorID, $0.controllerIdentity.productID) < (
          $1.controllerIdentity.vendorID, $1.controllerIdentity.productID
        )
      }
      self.rawUSBProfileIdentifiers = rawUSB.sorted(by: modelOrder)
      hidProfileIdentifiers = hid.sorted(by: modelOrder)
    } catch { fatalError("[DeviceCatalog] Invalid controller catalog: \(error)") }
  }

  /// The exact catalog record for this identity; there is no default record.
  func record(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile? {
    profiles[key(for: identifier)]
  }

  private func key(for identifier: DeviceIdentifier) -> String {
    "\(identifier.controllerIdentity.vendorID):\(identifier.controllerIdentity.productID)"
  }

  private static func loadRecords() throws -> [ControllerRecordDocument] {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
      .filter { isControllerRecordFilename($0.lastPathComponent) }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    guard !urls.isEmpty else { throw CatalogError("controller catalog is empty") }

    let decoder = JSONDecoder()
    return try urls.map { url in
      let data = try Data(contentsOf: url)
      do {
        let record = try decoder.decode(ControllerRecordDocument.self, from: data)
        let expectedName = String(format: "%04x-%04x.json", record.vendorID, record.productID)
        guard url.lastPathComponent == expectedName else {
          throw CatalogError("\(url.path): filename must be \(expectedName)")
        }
        return record
      } catch { throw CatalogError("\(url.path): \(error)") }
    }
  }

  private static func isControllerRecordFilename(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(5)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  /// The runtime profile for one decoded record; the record probe plan builds on it too.
  static func makeRuntimeProfile(_ record: ControllerRecordDocument) throws -> DeviceRuntimeProfile
  {
    guard (1...65_535).contains(record.vendorID), (0...65_535).contains(record.productID) else {
      throw CatalogError("invalid controller identity \(record.vendorID):\(record.productID)")
    }
    let protocolInfo = record.protocolInfo
    let defaultEndpoints = defaultEndpoints(for: protocolInfo.protocolID)
    let inputEndpoint = record.usb?.endpoints?.input ?? defaultEndpoints.input
    let outputEndpoint = record.usb?.endpoints?.output ?? defaultEndpoints.output
    if record.usb != nil
      && !protocolInfo.protocolID.usesRawUSB(storedVariant: protocolInfo.protocolVariant)
    {
      throw CatalogError("USB overrides require a raw-USB protocol family")
    }
    if let configuration = record.usb?.configuration, configuration != "set1-before-claim" {
      throw CatalogError("unsupported USB configuration \(configuration)")
    }
    let settleMilliseconds = record.usb?.postHandshakeSettleMilliseconds ?? 0
    let keepAlivePolicy: GIPKeepAlivePolicy =
      protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled } ?? .enabled

    return DeviceRuntimeProfile(
      recordID: String(format: "%04x-%04x", record.vendorID, record.productID),
      virtualProfile: .default,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(inputEndpoint),
        outputEndpoint: UInt8(outputEndpoint),
        hasEndpointOverride: record.usb?.endpoints != nil,
        needsSetConfiguration: record.usb?.configuration == "set1-before-claim",
        postHandshakeSettleNanoseconds: UInt64(settleMilliseconds)
          * DeviceTransportProfile.nanosecondsPerMillisecond
      ),
      physicalProtocolID: protocolInfo.protocolID,
      physicalProtocolVariant: protocolInfo.protocolVariant,
      quirks: protocolInfo.quirks,
      capabilityDelta: record.capabilities,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: protocolInfo.initialization ?? GIPStartupPacket.defaultSequence,
      gipKeepAlivePolicy: keepAlivePolicy,
      assemblyPolicy: protocolInfo.assembly
    )
  }

  /// The runtime profile of a row that names only this family and stored variant: default
  /// endpoints on interface 0, the default GIP initialization and keep-alive, and no quirks or
  /// capability deltas. Interface-signature bindings of uncatalogued devices run with it.
  static func familyRuntimeProfile(
    _ protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    needsSetConfiguration: Bool
  ) -> DeviceRuntimeProfile {
    let endpoints = defaultEndpoints(for: protocolID)
    return DeviceRuntimeProfile(
      recordID: nil,
      virtualProfile: .default,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(endpoints.input),
        outputEndpoint: UInt8(endpoints.output),
        needsSetConfiguration: needsSetConfiguration
      ),
      physicalProtocolID: protocolID,
      physicalProtocolVariant: protocolID.storesVariant ? variant : nil,
      quirks: [],
      capabilityDelta: .none,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: GIPStartupPacket.defaultSequence,
      gipKeepAlivePolicy: .enabled,
      assemblyPolicy: nil
    )
  }

  private static func defaultEndpoints(
    for protocolID: PhysicalProtocolID
  ) -> (input: Int, output: Int) {
    switch protocolID {
    case .xboxXUSB: (input: 129, output: 1)
    case .xboxXID: (input: 129, output: 2)
    default: (input: 130, output: 2)
    }
  }

  private struct CatalogError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
  }
}
