import Combine
import SwiftUI

#if DEBUG
/// HomeView invalidation fan-out (perf review 2026-10-17, finding #1): counts `body` evaluations of
/// Home and the row/card views under it, so a UI leg can measure how many bodies one hero focus
/// commit re-runs. DEBUG only.
///
/// `tick` is called from inside `body` and must not publish there, so it only bumps a dictionary;
/// a 0.5 s timer copies the counts into `snapshot` when they moved, and `HomeBodyCountLabel` (a
/// leaf, so its own re-render costs nothing else) exposes it as the invisible `debug_bodycounts`
/// accessibility label: `HomeView=12 CatalogRowView=40 …`.
@MainActor
final class HomeBodyCounter: ObservableObject {
    static let shared = HomeBodyCounter()

    /// Names in the order the label prints them.
    static let names = ["HomeView", "HomeRowsList", "CatalogRowView", "ContinueWatchingRow",
                        "UpcomingRow", "CollectionRowView", "InlineTrailerCard", "PosterCard"]

    private var counts: [String: Int] = [:]
    private var dirty = false
    private var timer: AnyCancellable?
    @Published private(set) var snapshot = "-"

    private init() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.flush() }
    }

    nonisolated static func tick(_ name: String) {
        MainActor.assumeIsolated {
            shared.counts[name, default: 0] += 1
            shared.dirty = true
        }
    }

    private func flush() {
        guard dirty else { return }
        dirty = false
        snapshot = Self.names.map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: " ")
    }
}

/// Invisible, harness-readable `debug_bodycounts` (see `HomeBodyCounter`).
struct HomeBodyCountLabel: View {
    @ObservedObject private var counter = HomeBodyCounter.shared

    var body: some View {
        Text(verbatim: "debug_bodycounts \(counter.snapshot)")
            .font(.system(size: 8))
            .opacity(0.011)
            .accessibilityIdentifier("debug_bodycounts")
    }
}
#endif
