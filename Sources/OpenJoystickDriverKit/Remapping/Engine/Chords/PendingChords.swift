import Foundation

struct RemappingPendingChordPress {
  let source: RemappingSource
  let uptime: UInt64
  let deadline: UInt64
  let axisValue: Float?
}

extension RemappingDeviceState {
  var pendingChordDeadline: UInt64? {
    chords.pendingChordPresses.map { resolvedDeadline($0) }.min()
  }

  func resolvedDeadline(_ press: RemappingPendingChordPress) -> UInt64 {
    deferredChordDeadline(for: press.source) ?? press.deadline
  }

  mutating func bufferChordPress(_ source: RemappingSource, at uptime: UInt64) -> Bool {
    let windows = effectiveChords.filter { $0.mode == .simultaneous && $0.sources.contains(source) }
      .map(\.windowMs)
    guard let window = windows.max() else { return false }
    let (end, overflow) = uptime.addingReportingOverflow(UInt64(window * 1_000_000) + 1)
    let axisValue: Float?
    if case .axisDirection(let axis, _) = source {
      axisValue = analog.physicalAxes[axis]
    } else {
      axisValue = nil
    }
    chords.pendingChordPresses.append(
      RemappingPendingChordPress(
        source: source,
        uptime: uptime,
        deadline: overflow ? .max : end,
        axisValue: axisValue
      )
    )
    return true
  }
}

extension RemappingEngineState {
  mutating func replayPendingChordPresses(
    device: inout RemappingDeviceState,
    at uptime: UInt64,
    releasing source: RemappingSource? = nil
  ) -> [RemappingEngineAction] {
    let ready = device.chords.pendingChordPresses.filter {
      device.resolvedDeadline($0) <= uptime || $0.source == source
    }
    let readySources = Set(ready.map(\.source))
    device.chords.pendingChordPresses.removeAll { readySources.contains($0.source) }
    var actions: [RemappingEngineAction] = []
    for press in ready {
      device.chords.replayedChordSources.insert(press.source)
      for binding in device.binding(for: press.source)?.expandedActions ?? [] {
        actions += processAction(
          binding,
          isActive: true,
          suppressed: false,
          device: &device,
          at: press.uptime
        )
      }
      for index in device.chords.sequenceHistory.indices {
        if device.chords.sequenceHistory[index].source == press.source,
          device.chords.sequenceHistory[index].uptime == press.uptime
        {
          device.chords.sequenceHistory[index].awaitingChord = false
        }
      }
      for index in device.chords.deferredSequences.indices {
        device.chords.deferredSequences[index].awaitingSources.remove(press.source)
      }
      actions += processSequences(for: &device, at: uptime)
      let replayAxis: (RemappingAxis, Float)?
      if press.source == source, case .axisDirection(let axis, _) = press.source,
        let value = press.axisValue
      {
        replayAxis = (axis, value)
      } else {
        replayAxis = nil
      }
      actions += device.updatePassthrough(replayingAxis: replayAxis)
    }
    return actions
  }
}
