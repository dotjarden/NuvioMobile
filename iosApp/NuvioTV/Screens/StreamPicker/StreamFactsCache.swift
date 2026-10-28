import Foundation
import SharedCore

/// Parsed stream facts by row key, for one load of the picker. The Kotlin parse is ~99% of a row
/// build, and an add-on republish rebuilds its whole group, so without this every append re-parsed
/// every row. The key is the stream-identity row key (`StreamsViewModel.rowKeys`), which survives
/// debrid URL swaps; the view model clears the cache when a new load starts.
@MainActor
final class StreamFactsCache {
    private var facts: [String: StreamFacts] = [:]
    /// Parses since the last `clear()` or `resetMissCount()`; the DEBUG probe and the tests read it.
    private(set) var missCount = 0

    /// The cached facts for `key`, parsing `stream` only on a miss.
    func facts(forKey key: String, stream: StreamItem) -> StreamFacts {
        if let hit = facts[key] { return hit }
        let parsed = StreamFactsParser.shared.parse(stream: stream)
        facts[key] = parsed
        missCount += 1
        return parsed
    }

    func resetMissCount() { missCount = 0 }

    func clear() {
        facts.removeAll()
        missCount = 0
    }
}
