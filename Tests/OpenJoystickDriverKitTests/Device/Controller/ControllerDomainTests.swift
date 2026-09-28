import Testing

@testable import OpenJoystickDriverKit

struct ControllerDomainTests {
  @Test
  func bipolarValueClampsTheAsymmetricMinimum() {
    #expect(BipolarValue(Int16.min).rawValue == -32767)
    #expect(BipolarValue(-32767).rawValue == -32767)
    #expect(BipolarValue(0) == .center)
    #expect(BipolarValue(Int16.max).rawValue == 32767)
    #expect(BipolarValue.min.rawValue == -BipolarValue.max.rawValue)
  }

  @Test
  func unipolarValueSpansTheFullUnsignedRange() {
    #expect(UnipolarValue.min.rawValue == 0)
    #expect(UnipolarValue.max.rawValue == 65535)
  }

  @Test
  func monotonicTimestampsOrderByNanoseconds() {
    let earlier = MonotonicTimestamp(nanoseconds: 1)
    let later = MonotonicTimestamp(nanoseconds: 2)
    #expect(earlier < later)
    #expect(!(later < earlier))
    #expect(later == MonotonicTimestamp(nanoseconds: 2))
  }

  @Test
  func controlIDsMatchTheStandardControlList() {
    let standardControls = [
      "dpad", "left-stick-x", "left-stick-y", "right-stick-x", "right-stick-y", "left-stick-click",
      "right-stick-click", "face-south", "face-east", "face-west", "face-north", "left-shoulder",
      "right-shoulder", "left-trigger", "right-trigger", "left-trigger-button",
      "right-trigger-button", "view", "menu", "guide", "share", "capture", "touchpad-click",
      "microphone", "paddle-left-1", "paddle-left-2", "paddle-right-1", "paddle-right-2",
      "auxiliary-1", "auxiliary-2", "auxiliary-3", "auxiliary-4", "auxiliary-5", "auxiliary-6",
      "auxiliary-7", "auxiliary-8", "left-stick-touch", "right-stick-touch", "left-trackpad-click",
      "right-trackpad-click", "left-trackpad-touch", "right-trackpad-touch",
    ]

    #expect(ControlID.allCases.map(\.rawValue) == standardControls)
  }
}
