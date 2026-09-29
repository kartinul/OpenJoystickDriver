import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct CoreGraphicsAccessTests {
  @Test
  func preflightReportsOnlyGrantedOrNotAuthorized() {
    #expect(makeAccess(preflight: [true]).currentState() == .granted)
    #expect(makeAccess(preflight: [false]).currentState() == .notAuthorized)
  }

  @Test
  func requestReturnIsIgnoredAndGrantedStateIsReadBack() {
    let probe = AccessProbe(preflight: [false, true], requestResult: false)
    let access = CoreGraphicsPostEventAccess(probe: probe)

    #expect(access.requestAccess() == .granted)
    #expect(probe.requestCount == 1)
    #expect(probe.preflightCount == 2)
  }

  @Test
  func successfulRequestReturnIsNotTreatedAsGrant() {
    let probe = AccessProbe(preflight: [false], requestResult: true)
    let access = CoreGraphicsPostEventAccess(probe: probe)

    #expect(access.requestAccess() == .notAuthorized)
    #expect(probe.requestCount == 1)
    #expect(probe.preflightCount == 2)
  }

  @Test
  func alreadyGrantedAccessDoesNotRequestAgain() {
    let probe = AccessProbe(preflight: [true], requestResult: false)
    let access = CoreGraphicsPostEventAccess(probe: probe)

    #expect(access.requestAccess() == .granted)
    #expect(probe.requestCount == 0)
    #expect(probe.preflightCount == 1)
  }

  private func makeAccess(preflight: [Bool]) -> CoreGraphicsPostEventAccess {
    CoreGraphicsPostEventAccess(probe: AccessProbe(preflight: preflight, requestResult: false))
  }
}
