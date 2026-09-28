import Foundation
import Testing

@testable import OpenJoystickDriverKit

final class RecoveryInputParser: PhysicalProtocolDriver, @unchecked Sendable {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: (red: UInt8, green: UInt8, blue: UInt8)? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  private let lock = NSLock()
  private var storedResetCount = 0

  var resetCount: Int { lock.withLock { storedResetCount } }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    data == Data([1]) ? ControllerEvent([.press(.faceSouth)], at: receivedAt.nanoseconds) : nil
  }

  func resetProtocolState() { lock.withLock { storedResetCount += 1 } }
}

final class RecoveryRumbleParser: PhysicalProtocolDriver, @unchecked Sendable {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities(rumbleMotors: [
    .leftMain, .rightMain, .leftTrigger, .rightTrigger,
  ])
  let defaultColor: (red: UInt8, green: UInt8, blue: UInt8)? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    data == Data([1]) ? ControllerEvent([.press(.faceSouth)], at: receivedAt.nanoseconds) : nil
  }

  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let intensities: RumbleIntensities
    switch command {
    case .setRumble(let requested, _): intensities = requested
    case .stopRumble: intensities = .off
    default: throw .unsupportedCapability(command.capability)
    }
    let bytes = [PhysicalRumbleMotor.leftMain, .rightMain, .leftTrigger, .rightTrigger].map {
      intensities[$0].byte
    }
    return PhysicalOutputPlan(writes: [
      .usb(PhysicalUSBOutputPacket(endpoint: 2, bytes: bytes, timeoutMilliseconds: 2_000))
    ])
  }

  /// The USB packets of one rumble request.
  func rumblePackets(
    _ left: UInt8,
    _ right: UInt8,
    _ lt: UInt8,
    _ rt: UInt8
  ) -> [PhysicalUSBOutputPacket] {
    let intensities: [PhysicalRumbleMotor: UInt8] = [
      .leftMain: left, .rightMain: right, .leftTrigger: lt, .rightTrigger: rt,
    ]
    let command = ControllerOutputCommand.setRumble(
      RumbleIntensities(bytes: intensities),
      duration: .milliseconds(0)
    )
    return encoded(command)?.writes.usbPackets ?? []
  }
}

actor RecoveryUSBProvider: USBTransportProvider {
  private var sessions: [RecoveryUSBSession]
  private var listedDevices: [USBTransportDevice]
  private(set) var openCount = 0
  private(set) var openedDevices: [USBTransportDevice] = []
  private(set) var resolutionGateReached = false
  private var shouldGateNextResolution = false
  private var resolutionGateContinuation: CheckedContinuation<Void, Never>?

  init(sessions: [RecoveryUSBSession], devices: [USBTransportDevice] = []) {
    self.sessions = sessions
    listedDevices = devices
  }

  func devices() -> [USBTransportDevice] { listedDevices }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession {
    openCount += 1
    openedDevices.append(device)
    guard !sessions.isEmpty else { throw USBTransportError.notFound }
    return sessions.removeFirst()
  }

  func resolveTransport(
    for _: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    if shouldGateNextResolution {
      shouldGateNextResolution = false
      resolutionGateReached = true
      await withCheckedContinuation { resolutionGateContinuation = $0 }
    }
    return USBTransportResolution(profile: configured)
  }

  func gateNextResolution() { shouldGateNextResolution = true }

  func setDevices(_ devices: [USBTransportDevice]) { listedDevices = devices }

  func releaseResolutionGate() {
    resolutionGateContinuation?.resume()
    resolutionGateContinuation = nil
  }
}

actor RecoveryHIDBackend: HIDAccessBackend {
  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { $0.finish() } }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { [] }

  func setOutputReport(
    locationID _: UInt32,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setOutputReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    locationID _: UInt32,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func getFeatureReport(
    locationID _: UInt32,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func getFeatureReport(
    connection _: HIDDeviceConnection,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func releaseInputClaim(locationID _: UInt32) -> PhysicalHIDClaimResult { .unavailable }

  func reacquireInputClaim(locationID _: UInt32) -> PhysicalHIDClaimResult { .unavailable }

  func routeElementValues(connection _: HIDDeviceConnection) {}
}

actor RecoveryUSBSession: USBTransportSession {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  let readError: USBTransportError
  private var readResults: [Result<[UInt8], USBTransportError>]
  private(set) var closeCount = 0
  private(set) var writes: [[UInt8]] = []
  private(set) var readCount = 0
  var writeCount: Int { writes.count }
  var inputOwnership: HIDInputOwnership { closeCount == 0 ? .exclusive : .unknown }

  init(readError: USBTransportError) {
    self.readError = readError
    readResults = []
  }

  init(readResults: [Result<[UInt8], USBTransportError>], readError: USBTransportError) {
    self.readResults = readResults
    self.readError = readError
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    guard closeCount == 0 else { throw USBTransportError.disconnected }
    writes.append(data)
    return data.count
  }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    readCount += 1
    if !readResults.isEmpty {
      switch readResults.removeFirst() {
      case .success(let bytes): return bytes
      case .failure(let error): throw error
      }
    }
    throw readError
  }

  func close() {
    guard closeCount == 0 else { return }
    closeCount = 1
  }
}

actor RecoveryOwnershipGate {
  private(set) var accessDeniedReportStarted = false
  private var isReleased = false
  private var blockedReport: CheckedContinuation<Void, Never>?

  func blockAccessDeniedReport() async {
    accessDeniedReportStarted = true
    guard !isReleased else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      blockedReport = continuation
    }
  }

  func release() {
    isReleased = true
    blockedReport?.resume()
    blockedReport = nil
  }
}

actor RecoveryStopCompletion {
  private(set) var isComplete = false
  func markComplete() { isComplete = true }
}

final class RecoveryGatedOutputDispatcher: OutputDispatcher, ControllerInputOwnershipListener,
  ControllerLifecycleListener, @unchecked Sendable
{
  private let stateLock = NSLock()
  private let gate: RecoveryOwnershipGate
  private var storedOwnershipReports: [HIDInputOwnership] = []
  private var storedDidStopController = false

  var suppressOutput = false
  var ownershipReports: [HIDInputOwnership] { stateLock.withLock { storedOwnershipReports } }
  var didStopController: Bool { stateLock.withLock { storedDidStopController } }

  init(gate: RecoveryOwnershipGate) { self.gate = gate }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}
  func activateOutput(for _: DeviceIdentifier) {}

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) async {
    if ownership == .accessDenied { await gate.blockAccessDeniedReport() }
    stateLock.withLock { storedOwnershipReports.append(ownership) }
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) {
    stateLock.withLock { storedDidStopController = true }
  }
}

final class RecoveryOutputDispatcher: OutputDispatcher, ControllerInputOwnershipListener,
  @unchecked Sendable
{
  private let stateLock = NSLock()
  private var storedOwnershipReports: [HIDInputOwnership] = []
  private var storedDispatchedStates: [ControllerState] = []
  private var storedPresenceCount = 0

  var suppressOutput = false
  /// Activations, which announce a present controller to the virtual output.
  var presenceCount: Int { stateLock.withLock { storedPresenceCount } }
  var ownershipReports: [HIDInputOwnership] { stateLock.withLock { storedOwnershipReports } }
  var dispatchedStates: [ControllerState] { stateLock.withLock { storedDispatchedStates } }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: DeviceIdentifier
  ) { stateLock.withLock { storedDispatchedStates.append(event.state) } }

  func activateOutput(for _: DeviceIdentifier) { stateLock.withLock { storedPresenceCount += 1 } }

  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: DeviceIdentifier
  ) { stateLock.withLock { storedOwnershipReports.append(ownership) } }
}

extension DevicePipeline {
  func activateForTesting() { isActive = true }
  func setUSBHandleForTesting(_ handle: any USBTransportSession) { usbHandle = handle }
  func usbRunTaskForTesting() -> Task<Void, Never>? { runTask }
}

extension DeviceManager {
  func setPhysicalOutputForTesting(
    _ output: RemappingPhysicalOutput,
    owner: UUID,
    identifier: DeviceIdentifier
  ) -> PhysicalOutputChannel {
    physicalOutputOwnership.setMapping(output, active: true, owner: owner, for: identifier)
  }

  var mappingClaimCountForTesting: Int { physicalOutputOwnership.mappingClaimCount }
}
