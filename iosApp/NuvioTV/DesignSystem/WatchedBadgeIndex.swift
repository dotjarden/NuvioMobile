import Observation
import SharedCore
import SwiftUI

// FEAT-64 (Steven, beta.19-rc5 verdict 2026-10-17: "marking a film watched shows no tick"): the
// watched tick on Home and collection rows. Library draws `PosterCard.watchBadge` from its own view
// model; catalog rows had no source for it. This is that source: ONE app-wide index fed by the
// shared `WatchedRepository`'s two flows, so no card runs a task or calls the repository, and a
// mark from the hold menu (which writes the repository) shows its tick with no refresh.

/// The watched state of every title, as two key sets, and the hold menu's rule over them
/// (`TitleHoldMenuPolicy.effectiveWatched`): a movie is watched when its title is marked; a series
/// when its title is marked or it is fully watched (`fullyWatchedSeriesKeys`). A series with some
/// episodes watched is not. Pure, so `WatchedBadgeIndexTests` can feed it the Kotlin key strings.
struct WatchedBadgeSnapshot: Equatable {
    /// Title-level marks (`season`/`episode` unset), as `titleKey`s.
    var marked: Set<String> = []
    /// Fully watched series, as `titleKey`s.
    var fullyWatched: Set<String> = []

    static let empty = WatchedBadgeSnapshot()

    /// From `WatchedUiState.watchedKeys` and `WatchedRepository.fullyWatchedSeriesKeys`, both in the
    /// shared `watchedKey` form `"<type>:<id>:<season or -1>:<episode or -1>"`. Episode keys are
    /// skipped: one watched episode never ticks its show.
    init(watchedKeys: some Sequence<String>, fullyWatchedSeriesKeys: some Sequence<String>) {
        marked = Set(watchedKeys.compactMap(Self.titleKey(fromWatchedKey:)))
        fullyWatched = Set(fullyWatchedSeriesKeys.compactMap(Self.titleKey(fromWatchedKey:)))
    }

    init() {}

    /// The hold menu's rule (`TitleHoldMenuPolicy.effectiveWatched` + `isSeries`), so the tick and
    /// the menu's "Mark as Watched / Unwatched" label never disagree.
    func isWatched(id: String, type: String) -> Bool {
        let key = Self.titleKey(type: type, id: id)
        if marked.contains(key) { return true }
        return TitleHoldMenuPolicy.isSeries(type: type) && fullyWatched.contains(key)
    }

    // MARK: Keys

    /// The type family the shared `watchedItemTypeAliases` matches across: movie/film are one title,
    /// series/show/tv/tvshow/anime are one title (lowercased); anything else is its trimmed self.
    static func typeFamily(_ type: String) -> String {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "movie", "film": return "movie"
        case "series", "show", "tv", "tvshow", "anime": return "series"
        default: return trimmed
        }
    }

    /// `"<family>|<id>"`: the shared `isWatched(id:type:)` matches any alias of the type with the
    /// trimmed id, which is exactly one family key.
    static func titleKey(type: String, id: String) -> String {
        "\(typeFamily(type))|\(id.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// A title-level shared key (`"movie:tt1:-1:-1"`) → `titleKey`; nil for an episode key or a
    /// malformed one. Ids may contain colons (`"kitsu:123"`), so the type is the text before the
    /// FIRST colon and the id runs up to the `":-1:-1"` suffix.
    static func titleKey(fromWatchedKey raw: String) -> String? {
        let suffix = ":-1:-1"
        guard raw.hasSuffix(suffix) else { return nil }
        let head = raw.dropLast(suffix.count)
        guard let colon = head.firstIndex(of: ":") else { return nil }
        let type = String(head[..<colon])
        let id = String(head[head.index(after: colon)...])
        guard !type.isEmpty, !id.isEmpty else { return nil }
        return titleKey(type: type, id: id)
    }
}

/// The app-wide watched index the catalog rows read (`WatchedBadgeReader`). Injected once at the
/// root (`ContentView`, `.environment(WatchedBadgeIndex.shared)`).
///
/// Observation scope (swiftui-ui-patterns, performance): `snapshot` is the one observed property,
/// read only inside `WatchedBadgeReader`'s body, a leaf per card. A mark replaces it once; the rows
/// around the cards never read it, so they never re-render for it.
///
/// Profile switch and sign-out: the repository clears and republishes both flows
/// (`onProfileChanged`, `clearLocalState`), so the index follows with no reset of its own; `reset()`
/// is the same empty state for tests.
@MainActor
@Observable
final class WatchedBadgeIndex {
    static let shared = WatchedBadgeIndex()

    private(set) var snapshot = WatchedBadgeSnapshot.empty

    @ObservationIgnored private var watchedKeys: Set<String> = []
    @ObservationIgnored private var fullyWatchedKeys: Set<String> = []
    @ObservationIgnored private var watchers: [FlowWatcher] = []

    init() {}

    /// Subscribes to the repository's two flows. Idempotent; the root calls it once the profile is
    /// entered.
    func start() {
        guard watchers.isEmpty else { return }
        WatchedRepository.shared.ensureLoaded()
        watchers.append(FlowWatcherKt.watch(WatchedRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? WatchedUiState else { return }
            self.receive(watchedKeys: state.watchedKeys, fullyWatchedSeriesKeys: nil)
        })
        watchers.append(FlowWatcherKt.watch(WatchedRepository.shared.fullyWatchedSeriesKeys) { [weak self] emitted in
            // A Kotlin `Set<String>` arrives as an NSSet subclass; bridge either form.
            let keys = (emitted as? Set<String>)
                ?? (emitted as? NSSet).map { Set($0.compactMap { $0 as? String }) }
            guard let self, let keys else { return }
            self.receive(watchedKeys: nil, fullyWatchedSeriesKeys: keys)
        })
    }

    /// One flow emitted (nil = that side unchanged). Rebuilds the snapshot and publishes it only
    /// when it changed, so a republish of the same marks re-renders nothing.
    func receive(watchedKeys: Set<String>?, fullyWatchedSeriesKeys: Set<String>?) {
        if let watchedKeys { self.watchedKeys = watchedKeys }
        if let fullyWatchedSeriesKeys { self.fullyWatchedKeys = fullyWatchedSeriesKeys }
        let next = WatchedBadgeSnapshot(watchedKeys: self.watchedKeys,
                                        fullyWatchedSeriesKeys: self.fullyWatchedKeys)
        if next != snapshot { snapshot = next }
    }

    func reset() {
        watchedKeys = []
        fullyWatchedKeys = []
        if snapshot != .empty { snapshot = .empty }
    }

    func isWatched(_ item: MetaPreview) -> Bool {
        snapshot.isWatched(id: item.id, type: item.type)
    }

    /// The badge a catalog card draws: the tick, or nil. No progress bar on these rows (Continue
    /// Watching owns progress).
    func badge(for item: MetaPreview) -> PosterWatchBadge? {
        isWatched(item) ? PosterWatchBadge(isWatched: true, progress: nil) : nil
    }
}

/// FEAT-64: the leaf that reads the index for ONE card and hands its badge to the card builder, so
/// a watched change re-renders these leaves and not the row (`CatalogRowView.card(for:)`). With no
/// index in the environment (a preview, a test host) it hands nil.
struct WatchedBadgeReader<Content: View>: View {
    let item: MetaPreview
    @ViewBuilder let content: (PosterWatchBadge?) -> Content
    @Environment(WatchedBadgeIndex.self) private var index: WatchedBadgeIndex?

    var body: some View {
        content(index?.badge(for: item))
    }
}
