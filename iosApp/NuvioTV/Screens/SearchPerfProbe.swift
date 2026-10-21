#if DEBUG
import Foundation
import SharedCore

/// BUG-155 (P2; Steven, beta.19-rc3 follow-ups 2026-10-14): while typing a search, the caret sat one
/// letter behind the text on screen and the results took a while to land. Two causes, two fixes:
/// `SearchContent` re-ran its whole body on every keystroke because it bound the live field text
/// (main-thread work between the keystroke and the caret draw), and a superseded query's HTTP
/// fetches never stopped (`CatalogInflightRequests` in shared `CatalogData.kt`), so the live
/// query's requests queued behind the dead ones.
///
/// This probe measures both, DEBUG only, as console lines (no UI):
///
///     [SearchPerf] key n=<keystrokes> body=<SearchContent bodies since that keystroke> dt=<ms since it>
///     [SearchPerf] fire q="<query>" inflight=<shared catalog fetches running> keys=<since last fire> maxBody=<worst keystroke so far>
///     [SearchPerf] results q="<query>" first=<ms fire → first rows> last=<ms fire → settled> cancelledFetches=<n> legacy=<0|1>
///     [SearchPerf] catalog q="<query>" key=<manifestId:type:catalogId> outcome=<ok|empty|failed> ms=<n> err=<class|-> retry=<ok|failed|none>
///
/// The `catalog` line (BUG-208) prints from Kotlin (`SearchRepository.fetchOutcomeWithRetry`), one
/// per search catalog, once `applyLegacySwitch` turns `CatalogInflightStats.searchCatalogProbe` on.
///
/// A `key` line prints only when `SearchContent` re-evaluates inside a keystroke's window (the
/// window closes at the next keystroke, at the debounce firing, or when the view model publishes
/// results), so with the fix a typed word prints none after its first letter (the empty →
/// non-empty edge swaps the idle page for the results page: one body). `cancelledFetches` counts
/// from the first letter typed into an empty field. The last `results` line, plus the counters, is
/// also the `debug_search_perf` accessibility probe the UI leg reads (`probeLine`).
///
/// `-debug.searchLegacy YES` restores the pre-fix behaviour of both halves for a before/after on
/// one build: `SearchContent` back on the live binding, abandoned fetches left running.
enum SearchPerfProbe {
    /// Read once per launch: the argument domain sets it.
    static let legacy: Bool = UserDefaults.standard.bool(forKey: "debug.searchLegacy")

    nonisolated(unsafe) private static var keystrokes = 0
    nonisolated(unsafe) private static var keysSinceFire = 0
    nonisolated(unsafe) private static var keyUptime: TimeInterval?
    nonisolated(unsafe) private static var bodiesInWindow = 0
    nonisolated(unsafe) private static var maxBodiesPerKey = 0
    nonisolated(unsafe) private static var fireUptime: TimeInterval?
    nonisolated(unsafe) private static var firedQuery: String?
    nonisolated(unsafe) private static var firstMs: Int?
    nonisolated(unsafe) private static var settled = true
    nonisolated(unsafe) private static var cancelledBaseline: Int32 = 0
    nonisolated(unsafe) private static var lastResults = "-"

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    private static func ms(since start: TimeInterval?) -> Int {
        guard let start else { return -1 }
        return Int(((now() - start) * 1000).rounded())
    }
    private static var cancelledSinceSession: Int32 {
        CatalogInflightStats.shared.cancelled - cancelledBaseline
    }

    /// Applies the A/B switch to the shared fetch registry. Idempotent; called from `start()`.
    static func applyLegacySwitch() {
        CatalogInflightStats.shared.cancelAbandonedFetches = !legacy
        // BUG-208: one `[SearchPerf] catalog …` stdout line per search catalog (Kotlin side).
        CatalogInflightStats.shared.searchCatalogProbe = true
        if legacy { print("[SearchPerf] legacy=1 (-debug.searchLegacy): live binding, no fetch cancel") }
    }

    /// The field went from empty to non-empty: a new typing session.
    static func sessionStarted() {
        keystrokes = 0
        keysSinceFire = 0
        maxBodiesPerKey = 0
        cancelledBaseline = CatalogInflightStats.shared.cancelled
    }

    /// The query box's text changed (from its `didSet`, so it runs before SwiftUI renders).
    static func keystroke() {
        keystrokes += 1
        keysSinceFire += 1
        keyUptime = now()
        bodiesInWindow = 0
    }

    /// `SearchContent.body` ran.
    static func bodyEvaluated() {
        guard keyUptime != nil else { return }
        bodiesInWindow += 1
        maxBodiesPerKey = max(maxBodiesPerKey, bodiesInWindow)
        print("[SearchPerf] key n=\(keystrokes) body=\(bodiesInWindow) dt=\(ms(since: keyUptime))")
    }

    /// The view model is about to publish results: later bodies are not the keystroke's.
    static func closeKeyWindow() {
        keyUptime = nil
    }

    /// The debounce fired a search for `query`.
    static func fired(query: String) {
        closeKeyWindow()
        fireUptime = now()
        firedQuery = query
        firstMs = nil
        settled = false
        print("[SearchPerf] fire q=\"\(query)\" inflight=\(CatalogInflightStats.shared.inflight) keys=\(keysSinceFire) maxBody=\(maxBodiesPerKey)")
        keysSinceFire = 0
    }

    /// An emission of the active search arrived (not stale).
    static func emission(hasRows: Bool, isLoading: Bool) {
        closeKeyWindow()
        guard !settled, let fireUptime, let firedQuery else { return }
        if hasRows, firstMs == nil { firstMs = ms(since: fireUptime) }
        guard !isLoading else { return }
        settled = true
        let last = ms(since: fireUptime)
        let first = firstMs ?? -1
        lastResults = "q=\(firedQuery.replacingOccurrences(of: " ", with: "+")) first=\(first) last=\(last) cancelled=\(cancelledSinceSession)"
        print("[SearchPerf] results q=\"\(firedQuery)\" first=\(first) last=\(last) cancelledFetches=\(cancelledSinceSession) legacy=\(legacy ? 1 : 0)")
    }

    /// `search_perf keys=<n> maxBody=<m> inflight=<n> legacy=<0|1> <last results: q= first= last= cancelled=>`.
    static var probeLine: String {
        "search_perf keys=\(keystrokes) maxBody=\(maxBodiesPerKey) inflight=\(CatalogInflightStats.shared.inflight) legacy=\(legacy ? 1 : 0) \(lastResults)"
    }
}
#endif
