import Testing

@testable import OpenJoystickDriverKit

actor USBDiscoveryRecordingProvider: USBTransportProvider {
  private var currentDevices: [USBTransportDevice]
  private let physicalDevice: PhysicalDevice?
  private(set) var resolutionCount = 0
  private(set) var observationResolutionCount = 0

  init(devices: [USBTransportDevice], physicalDevice: PhysicalDevice? = nil) {
    currentDevices = devices
    self.physicalDevice = physicalDevice
  }

  func devices() -> [USBTransportDevice] { currentDevices }

  func setDevices(_ devices: [USBTransportDevice]) { currentDevices = devices }

  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) -> USBTransportResolution {
    resolutionCount += 1
    if physicalDevice != nil { observationResolutionCount += 1 }
    return USBTransportResolution(profile: configured, physicalDevice: physicalDevice)
  }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession { USBDiscoveryRecordingSession() }
}

private final class USBDiscoveryRecordingSession: USBTransportSession, @unchecked Sendable {
  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) -> Int { data.count }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.disconnected
  }
}

actor USBEnumerationPollingProvider: USBTransportProvider {
  enum Reply: Sendable {
    case devices([USBTransportDevice])
    case failure(USBTransportError)
  }

  private var replies: [Reply]

  init(replies: [Reply]) { self.replies = replies }

  func devices() throws -> [USBTransportDevice] {
    guard !replies.isEmpty else { return [] }
    switch replies.removeFirst() {
    case .devices(let devices): return devices
    case .failure(let error): throw error
    }
  }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession { throw USBTransportError.notSupported }
}

actor USBResolutionRaceProvider: USBTransportProvider {
  private let device: USBTransportDevice
  private let session = USBDiscoveryRecordingSession()
  private var resolutionSuspended = true
  private var resolutionContinuations: [CheckedContinuation<Void, Never>] = []
  private var resolutionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var openWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private(set) var resolutionCount = 0
  private(set) var openCount = 0

  init(device: USBTransportDevice) { self.device = device }

  func devices() -> [USBTransportDevice] { [device] }

  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    resolutionCount += 1
    signalWaiters(&resolutionWaiters, count: resolutionCount)
    if resolutionSuspended { await withCheckedContinuation { resolutionContinuations.append($0) } }
    return USBTransportResolution(profile: configured)
  }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession {
    openCount += 1
    signalWaiters(&openWaiters, count: openCount)
    return session
  }

  func waitForResolutionCount(_ count: Int) async {
    guard resolutionCount < count else { return }
    await withCheckedContinuation { resolutionWaiters.append((count, $0)) }
  }

  func resumeNextResolution() { resolutionContinuations.removeFirst().resume() }

  func waitForOpenCount(_ count: Int) async {
    guard openCount < count else { return }
    await withCheckedContinuation { openWaiters.append((count, $0)) }
  }

  func setResolutionSuspended(_ suspended: Bool) { resolutionSuspended = suspended }

  private func signalWaiters(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], count: Int)
  {
    var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
    for (target, continuation) in waiters {
      if count >= target { continuation.resume() } else { remaining.append((target, continuation)) }
    }
    waiters = remaining
  }
}
