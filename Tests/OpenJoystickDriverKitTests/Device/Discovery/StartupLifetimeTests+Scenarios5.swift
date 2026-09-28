import Foundation
import IOKit
import Testing

@testable import OpenJoystickDriverKit

enum HIDTeardownRaceTrigger {
  case accessFailure
  case denied
}

actor ScriptedHIDAccessBackend: HIDAccessBackend {
  private let delaysFirstStream: Bool
  private let closesSessionWhenStreamEnds: Bool
  private let session = ScriptedHIDSession()
  private var attempts = 0
  private var connectionSnapshots: [HIDDeviceConnectionSnapshot]? = []
  private var outputReportsEnabled = false
  private var outputReports: [PhysicalHIDOutputReport] = []
  private var outputReportConnectionIDs: [UUID] = []
  private var featureReportsEnabled = false
  private var featureReports: [PhysicalHIDOutputReport] = []
  private var featureReportTargets: [UUID?] = []
  private var featureReads = 0
  private var featureReadReportIDs: [UInt8] = []
  private var featureReadTargets: [UUID?] = []
  private var rejectedReports: [PhysicalHIDOutputReport] = []
  private var failingOutputReportCount = 0
  private var neutralMotorOutputGate: (started: StartupTestGate, release: StartupTestGate)?
  private var streams: [Int: AsyncStream<HIDDeviceEvent>] = [:]
  private var continuations: [Int: AsyncStream<HIDDeviceEvent>.Continuation] = [:]
  private var delayedFirstStream: CheckedContinuation<AsyncStream<HIDDeviceEvent>, Never>?

  /// `closesSessionWhenStreamEnds` models the IOHID backend, which closes its devices and rejects
  /// reports once the detection stream's consumer ends.
  init(delaysFirstStream: Bool = false, closesSessionWhenStreamEnds: Bool = false) {
    self.delaysFirstStream = delaysFirstStream
    self.closesSessionWhenStreamEnds = closesSessionWhenStreamEnds
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    attempts += 1
    let attempt = attempts
    let (stream, continuation) = AsyncStream<HIDDeviceEvent>.makeStream()
    if closesSessionWhenStreamEnds {
      continuation.onTermination = { [session] _ in session.close() }
    }
    streams[attempt] = stream
    continuations[attempt] = continuation
    guard delaysFirstStream, attempt == 1 else { return stream }
    return await withCheckedContinuation { delayedFirstStream = $0 }
  }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { connectionSnapshots }

  func setOutputReport(
    locationID _: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard outputReportsEnabled, !rejectedReports.contains(report), !failsOutputReport() else {
      return .unavailable
    }
    outputReports.append(report)
    if isNeutralMotorReport(report), let gate = neutralMotorOutputGate {
      neutralMotorOutputGate = nil
      await gate.started.open()
      await gate.release.wait()
    }
    return .success(())
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard connectionSnapshots?.contains(where: { $0.connection == connection }) == true,
      outputReportsEnabled, !failsOutputReport()
    else { return .unavailable }
    outputReportConnectionIDs.append(connection.connectionID)
    outputReports.append(report)
    if isNeutralMotorReport(report), let gate = neutralMotorOutputGate {
      neutralMotorOutputGate = nil
      await gate.started.open()
      await gate.release.wait()
    }
    return .success(())
  }

  func setFeatureReport(
    locationID _: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard featureReportsEnabled, !session.isClosed, !rejectedReports.contains(report) else {
      return .unavailable
    }
    featureReports.append(report)
    featureReportTargets.append(nil)
    return .success(())
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard connectionSnapshots?.contains(where: { $0.connection == connection }) == true,
      !session.isClosed, !rejectedReports.contains(report)
    else { return .unavailable }
    featureReports.append(report)
    featureReportTargets.append(connection.connectionID)
    return .success(())
  }

  func getFeatureReport(
    locationID _: UInt32,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    featureReads += 1
    featureReadReportIDs.append(request.reportID)
    featureReadTargets.append(nil)
    return .unavailable
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    featureReads += 1
    featureReadReportIDs.append(request.reportID)
    featureReadTargets.append(connection.connectionID)
    return .unavailable
  }

  func releaseInputClaim(locationID _: UInt32) -> PhysicalHIDClaimResult { .unavailable }

  func reacquireInputClaim(locationID _: UInt32) -> PhysicalHIDClaimResult { .unavailable }

  func routeElementValues(connection _: HIDDeviceConnection) {}

  func attemptCount() -> Int { attempts }

  func isSessionClosed() -> Bool { session.isClosed }

  func enableOutputReports() { outputReportsEnabled = true }

  func enableFeatureReports() { featureReportsEnabled = true }

  /// Location-routed output writes and all feature writes of `report` fail without being
  /// recorded.
  func reject(_ report: PhysicalHIDOutputReport) { rejectedReports.append(report) }

  func disableOutputReports() { outputReportsEnabled = false }

  /// The next `count` output writes fail on either route without being recorded.
  func failNextOutputReports(_ count: Int) { failingOutputReportCount = count }

  private func failsOutputReport() -> Bool {
    guard failingOutputReportCount > 0 else { return false }
    failingOutputReportCount -= 1
    return true
  }

  func clearOutputReports() { outputReports.removeAll() }

  func blockNextNeutralMotorOutput(started: StartupTestGate, release: StartupTestGate) {
    neutralMotorOutputGate = (started, release)
  }

  func recordedOutputReports() -> [PhysicalHIDOutputReport] { outputReports }

  func recordedOutputReportConnectionIDs() -> [UUID] { outputReportConnectionIDs }

  func recordedFeatureReports() -> [PhysicalHIDOutputReport] { featureReports }

  func recordedFeatureReportTargets() -> [UUID?] { featureReportTargets }

  func recordedFeatureReadCount() -> Int { featureReads }

  func recordedFeatureReadReportIDs() -> [UInt8] { featureReadReportIDs }

  /// The connection each feature read targeted; nil for a location-routed read.
  func recordedFeatureReadTargets() -> [UUID?] { featureReadTargets }

  func setConnectionSnapshots(_ snapshots: [HIDDeviceConnectionSnapshot]?) {
    connectionSnapshots = snapshots
  }

  func yield(_ event: HIDDeviceEvent, attempt: Int) { continuations[attempt]?.yield(event) }

  func fail(_ failure: PhysicalHIDFailure, attempt: Int) {
    continuations[attempt]?.yield(.accessFailure(failure))
    continuations[attempt]?.finish()
  }

  func finish(attempt: Int) { continuations[attempt]?.finish() }

  func releaseFirstStream() {
    guard let delayedFirstStream, let stream = streams[1] else { return }
    self.delayedFirstStream = nil
    delayedFirstStream.resume(returning: stream)
  }

  private func isNeutralMotorReport(_ report: PhysicalHIDOutputReport) -> Bool {
    report.reportID == 0x11 && report.bytes.count > 7 && report.bytes[3] == 0x01
      && report.bytes[6] == 0 && report.bytes[7] == 0
  }
}

private final class ScriptedHIDSession: @unchecked Sendable {
  private let lock = NSLock()
  private var closed = false

  var isClosed: Bool { lock.withLock { closed } }

  func close() { lock.withLock { closed = true } }
}

actor StartupTestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in self.continuation = continuation }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}

final class GatedStartupOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  private let lock = NSLock()
  private let firstDispatchStarted = StartupTestGate()
  private let releaseFirstDispatch = StartupTestGate()
  private var blockFirstEmptyBatch = true
  private var storedSuppression = false

  var suppressOutput: Bool {
    get { lock.withLock { storedSuppression } }
    set { lock.withLock { storedSuppression = newValue } }
  }

  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }

  func dispatch(_: ControllerEvent, labels _: ControllerButtonLabels, from _: DeviceIdentifier) {}

  /// Blocks the first activation until released.
  func activateOutput(for _: DeviceIdentifier) async {
    let shouldBlock = lock.withLock { () -> Bool in
      guard blockFirstEmptyBatch else { return false }
      blockFirstEmptyBatch = false
      return true
    }
    guard shouldBlock else { return }
    await firstDispatchStarted.open()
    await releaseFirstDispatch.wait()
  }

  func waitForBlockedDispatch() async { await firstDispatchStarted.wait() }

  func releaseBlockedDispatch() async { await releaseFirstDispatch.open() }
}

extension DeviceManager {
  func markStartedForTest() { isStarted = true }

  func setStoppingForTest(_ stopping: Bool) { isStopping = stopping }

  func setManualRumbleForTest(on identifier: DeviceIdentifier) {
    _ = physicalOutputOwnership.setManual(.rumble(motor: .leftMain, intensity: 1), for: identifier)
  }

  func holdPermissionWatchForTest() {
    permissionWatchTask = Task { try? await Task.sleep(for: .seconds(3_600)) }
  }

  func installHIDInitializationForTest(_ initialization: HIDDeviceInitialization) {
    hidInitializationTasks[hidInitializationKey(for: initialization.connection)] = initialization
  }

  func installLifecycleTasksForTest(
    permissionWatcher: Task<Void, Never>,
    initialization: HIDDeviceInitialization
  ) {
    permissionWatchTask = permissionWatcher
    hidInitializationTasks[hidInitializationKey(for: initialization.connection)] = initialization
  }

  func outputQueueForTest(for identifier: DeviceIdentifier) -> PhysicalHIDOutputSerialQueue? {
    hidOutputQueues[identifier]
  }

  func installOutputQueueForTest(
    _ queue: PhysicalHIDOutputSerialQueue,
    for identifier: DeviceIdentifier
  ) { hidOutputQueues[identifier] = queue }
}
