import Foundation

extension UserSpaceOutputDispatcher {
  final class Entry: @unchecked Sendable {
    let sender: UserSpaceReportSender
    let inputReportState: UserSpaceInputReportState
    private let lock = NSLock()
    private var closeTask: Task<Void, Never>?

    init(backend: any VirtualDeviceBackend, inputReportState: UserSpaceInputReportState) {
      sender = UserSpaceReportSender()
      self.inputReportState = inputReportState
      sender.attach(backend)
    }

    deinit { beginClose() }

    @discardableResult
    func beginClose() -> Task<Void, Never> {
      lock.withLock {
        if let closeTask { return closeTask }
        inputReportState.close()
        let task = sender.beginClose()
        closeTask = task
        return task
      }
    }

    func close() async { await beginClose().value }
  }
}
