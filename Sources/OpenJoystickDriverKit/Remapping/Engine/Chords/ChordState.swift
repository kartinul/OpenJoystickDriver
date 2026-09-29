import Foundation

struct RemappingChordState {
  var pendingChordPresses: [RemappingPendingChordPress] = []
  var consumedChordSources: Set<RemappingSource> = []
  var replayedChordSources: Set<RemappingSource> = []
  var activeChords: Set<UUID> = []
  var sequenceHistory: [RemappingSequenceHistoryEntry] = []
  var deferredSequences: [RemappingDeferredSequence] = []
}

struct RemappingSequenceHistoryEntry: Equatable {
  let source: RemappingSource
  let uptime: UInt64
  var awaitingChord: Bool = false
}
