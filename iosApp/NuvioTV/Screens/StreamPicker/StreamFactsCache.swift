import Foundation
import SharedCore

/// Parsed stream facts by row key, for one load of the picker. The Kotlin parse is ~99% of a row
/// build, and an add-on republish rebuilds its whole group, so without this every append re-parsed
/// every row. The key is the stream-identity row key (`StreamsViewModel.rowKeys`), which survives
/// debrid URL swaps, so it is not enough on its own: the parser also reads the URL, filename, size
/// and cache status. Each entry keeps the stream it was parsed from and counts as a hit only for an
/// equal stream (a prepared copy or a reordered duplicate re-parses). The view model clears the
/// cache when a new load starts.
@MainActor
final class StreamFactsCache {
    private var entries: [String: (stream: StreamItem, facts: StreamFacts)] = [:]
    /// Parses since the last `clear()`; the DEBUG probe and the tests read it.
    private(set) var missCount = 0

    /// The cached facts for `key` when it was parsed from an equal `stream`, else a fresh parse
    /// that replaces the entry.
    func facts(forKey key: String, stream: StreamItem) -> StreamFacts {
        if let entry = entries[key], entry.stream == stream { return entry.facts }
        let parsed = StreamFactsParser.shared.parse(stream: stream)
        entries[key] = (stream, parsed)
        missCount += 1
        return parsed
    }

    func clear() {
        entries.removeAll()
        missCount = 0
    }
}
