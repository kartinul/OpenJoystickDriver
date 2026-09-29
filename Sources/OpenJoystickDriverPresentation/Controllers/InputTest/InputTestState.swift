#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  protocol InputTestDeviceGateway: MotionCalibrationGateway {
    func controllerState(for selector: RuntimeDeviceSelector) async throws -> ControllerState?
    func sendControllerOutput(
      _ command: ControllerOutputCommand,
      for selector: RuntimeDeviceSelector
    ) async throws -> ControllerOutputResult
    func previewColor(
      for selector: RuntimeDeviceSelector,
      token: UUID,
      red: UInt8,
      green: UInt8,
      blue: UInt8
    ) async throws -> Bool
    func releaseColorPreview(for selector: RuntimeDeviceSelector, token: UUID) async throws -> Bool
  }

  /// View-owned physical-output values are isolated from session state so continuous controls do
  /// not invalidate the live input hierarchy or window chrome while they are being dragged.
  @MainActor
  final class InputTestOutputSettings: ObservableObject {
    @Published
    var rumbleIntensities: [PhysicalRumbleMotor: Double] = [:]
    @Published
    var rumbleDurationMilliseconds = 300.0
    @Published
    var playerIndicator: PhysicalPlayerIndicator = .off
    @Published
    var red = 0.0
    @Published
    var green = 122.0
    @Published
    var blue = 255.0
    @Published
    var brightness = 255.0
  }

  @MainActor
  final class InputTestViewModel: ObservableObject {
    @Published
    var device: ApplicationServiceDeviceDescription?
    @Published
    var sessionState: SessionState = .idle
    @Published
    var outputState: OutputState = .idle
    @Published
    var outputError: String?
    @Published
    var isDeviceConnected = false
    let liveState = InputTestLiveState()
    let outputSettings = InputTestOutputSettings()
    let motionCalibration: MotionCalibrationViewModel

    let gateway: any InputTestDeviceGateway
    let sampleIntervalNanoseconds: UInt64
    let sleep: Sleep
    let rumbleSleep: Sleep
    var samplingTask: Task<Void, Never>?
    var outputTask: Task<Void, Never>?
    var samplingGeneration: UInt64 = 0
    var isWindowActive = false
    var outputGeneration: UInt64 = 0
    var outputSelector: RuntimeDeviceSelector?
    var outputMayRequireRumbleStop = false
    let colorPreviewToken = UUID()
    var colorPreviewSelector: RuntimeDeviceSelector?

    init(
      gateway: any InputTestDeviceGateway,
      sampleIntervalNanoseconds: UInt64 = 33_333_333,
      sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) },
      rumbleSleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
      self.gateway = gateway
      motionCalibration = MotionCalibrationViewModel(gateway: gateway)
      self.sampleIntervalNanoseconds = sampleIntervalNanoseconds
      self.sleep = sleep
      self.rumbleSleep = rumbleSleep
    }
  }

#endif
