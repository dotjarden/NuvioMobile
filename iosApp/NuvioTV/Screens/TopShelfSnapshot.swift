import Combine
import Foundation
import SharedCore

/// Bridge between the app and the Top Shelf extension. The extension can't link SharedCore, so
/// the app mirrors the active profile's continue-watching rail into a small JSON snapshot in the
/// shared App Group container; the extension reads it and renders `TVTopShelfSectionedContent`.
///
/// `TopShelfItemSnapshot` is duplicated (structurally) in the extension's `ContentProvider.swift`
/// — keep the two Codable shapes in sync if fields change.
enum TopShelf {
    /// Must match the App Group registered on BOTH the app and extension targets in
    /// Signing & Capabilities, and the id in the extension's ContentProvider.
    static let appGroupId = "group.com.nuvio.media.NuvioTV"
    static let snapshotFilename = "top-shelf.json"

    /// The custom URL scheme the extension's actions launch the app with (registered on the
    /// NuvioTV target under Info → URL Types).
    static let urlScheme = "nuviotv"

    /// tvOS only permits writes inside Library/Caches of a group container (the container root
    /// is read-only under tvOS's no-persistent-storage policy). Caches can theoretically be
    /// purged, but the app rewrites the snapshot on every progress change, so that's fine.
    static var snapshotDirectoryURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("Library/Caches", isDirectory: true)
    }

    static var snapshotURL: URL? {
        snapshotDirectoryURL?.appendingPathComponent(snapshotFilename)
    }
}

/// One continue-watching entry, flattened to what the Top Shelf needs (art + labels) plus what a
/// deep link needs to resume playback or open the title (ids, type, season/episode).
struct TopShelfItemSnapshot: Codable, Equatable {
    let videoId: String
    let parentMetaId: String
    let parentMetaType: String
    let title: String
    let episodeTitle: String?
    let season: Int?
    let episode: Int?
    let poster: String?
    let background: String?
    let progressPercent: Double?
}

struct TopShelfSnapshot: Codable {
    let generatedAtEpochMs: Int64
    let items: [TopShelfItemSnapshot]
}

/// Lives at the ContentView root (started once a profile is entered). Watches the shared
/// watch-progress state and rewrites the App Group snapshot on every change — including profile
/// switches, since the repository re-emits for the newly scoped profile.
@MainActor
final class TopShelfUpdater: ObservableObject {
    private var watcher: FlowWatcher?
    private var sourceWatcher: FlowWatcher?
    private var traktSettingsWatcher: FlowWatcher?
    private var lastDaysCap: Int32?
    /// The last snapshot written, progress rounded to the whole percent (see `writeSnapshot`).
    private var lastWrittenItems: [TopShelfItemSnapshot]?
    /// Coalesces a burst of emissions (progress save + source + settings) into one write.
    private var pendingWrite: Task<Void, Never>?

    func start() {
        guard watcher == nil else { return }
        WatchProgressRepository.shared.ensureLoaded()
        CustomPosterUrlRepository.shared.ensureLoaded()   // A7: the pattern the snapshot applies
        watcher = FlowWatcherKt.watch(WatchProgressRepository.shared.uiState) { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleWrite() }
        }
        // BUG-75: the row's gates (active provider's dropped-show filter + recency window) live
        // outside uiState — a source switch or days-cap edit must rewrite the snapshot too.
        sourceWatcher = FlowWatcherKt.watch(WatchProgressRepository.shared.activeSourceState) { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleWrite() }
        }
        traktSettingsWatcher = FlowWatcherKt.watch(TraktSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let state = emitted as? TraktSettingsUiState else { return }
            DispatchQueue.main.async {
                guard let self, self.lastDaysCap != state.continueWatchingDaysCap else { return }
                self.lastDaysCap = state.continueWatchingDaysCap
                self.scheduleWrite()
            }
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        sourceWatcher?.cancel()
        sourceWatcher = nil
        traktSettingsWatcher?.cancel()
        traktSettingsWatcher = nil
        lastDaysCap = nil
        // Flush, don't drop: sign-out's last emission (the wiped, empty row) only arms the
        // debounce, and `stop()` follows at once. Cancelling would leave the previous account's
        // Continue Watching on the Top Shelf (review r1 P1).
        if pendingWrite != nil {
            pendingWrite?.cancel()
            pendingWrite = nil
            writeSnapshot()
        }
        // A profile switch or sign-out restarts the updater; its first snapshot must always land.
        lastWrittenItems = nil
    }

    /// Every watch-progress save emits (the players save every few seconds), and each used to
    /// rewrite the App Group file: ~3 writes per 11 s segment on device (2026-10-17). Writes now
    /// wait 0.5 s for the burst to settle and are skipped when nothing Top Shelf shows changed.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.pendingWrite = nil
            self?.writeSnapshot()
        }
    }

    /// Leaving the signed-in state: stop observing and write an EMPTY snapshot, whatever the
    /// order of the account wipe and this call. A real-account sign-out flips the auth gate before
    /// the Kotlin wipe runs, so `stop()`'s flush could still read the old account's rows (review
    /// r2 P2); and signing out from the profile picker (updater already stopped) never rewrote
    /// the file at all.
    func clearForSignOut() {
        pendingWrite?.cancel()
        pendingWrite = nil
        stop()
        lastWrittenItems = []
        write(items: [])
    }

    private func writeSnapshot() {
        guard TopShelf.snapshotURL != nil else {
            print("[TopShelf] App Group container is nil — App Groups capability missing/unsigned on the app target")
            return
        }

        // BUG-75: same provider-aware row Home builds (dropped shows and out-of-window entries
        // filtered), scanned short — Top Shelf only ever shows the first 10.
        let entries = WatchProgressRepository.shared.continueWatchingRow(limit: 20)
        // NuvioTV upstream 228820681 (A7): the Continue Watching custom poster pattern applies to
        // the Top Shelf's posters too, as it does to the in-app row. A pattern that resolves
        // nothing (blank, screen off, unsupported id) keeps the entry's own poster.
        let posterPattern = CustomPosterUrlRepository.shared.patternForScreen(screen: .continueWatching)
        let items = entries.prefix(10).map { entry in
            TopShelfItemSnapshot(
                videoId: entry.videoId,
                parentMetaId: entry.parentMetaId,
                parentMetaType: entry.parentMetaType,
                title: entry.title,
                episodeTitle: entry.episodeTitle,
                season: entry.seasonNumber?.value,
                episode: entry.episodeNumber?.value,
                poster: Self.customPoster(entry, pattern: posterPattern) ?? entry.poster,
                background: entry.background ?? entry.episodeThumbnail,
                // `progressFraction` covers both kinds of entry: a stored percentage (Trakt/Simkl)
                // or position / duration (local playback saves no percentage, so they used to
                // carry none and the Top Shelf showed no bar for them).
                progressPercent: entry.progressFraction > 0 ? Double(entry.progressFraction) * 100 : nil
            )
        }
        // Skip the write when the items are unchanged at Top Shelf's resolution: the progress bar
        // is compared to the whole percent, so a playing title rewrites ~once a minute, not on
        // every save.
        let comparable = items.map(Self.roundedForComparison)
        if comparable == lastWrittenItems { return }
        lastWrittenItems = comparable
        write(items: Array(items))
    }

    private func write(items: [TopShelfItemSnapshot]) {
        guard let url = TopShelf.snapshotURL else { return }
        let snapshot = TopShelfSnapshot(
            generatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            items: items
        )

        // Encode on main (cheap, ≤10 tiny items); write atomically so the extension never reads
        // a torn file.
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = TopShelf.snapshotDirectoryURL
        Self.writeQueue.async { [weak self] in
            do {
                if let directory {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try data.write(to: url, options: .atomic)
                print("[TopShelf] wrote \(snapshot.items.count) items to \(url.path)")
            } catch {
                print("[TopShelf] write failed: \(error)")
                // Not written: let the next change retry instead of matching the dedupe.
                Task { @MainActor [weak self] in self?.lastWrittenItems = nil }
            }
        }
    }

    /// Serial, so an older snapshot can never land after a newer one (with the dedupe, a stale
    /// file would otherwise persist until the next change).
    /// A7: the entry's parent title through the custom poster pattern, portrait shape (the Top
    /// Shelf draws posters); nil when the pattern does not apply.
    static func customPoster(_ entry: WatchProgressEntry, pattern: String) -> String? {
        guard !pattern.isEmpty else { return nil }
        return CustomPosterUrls.shared.resolveWithPattern(
            pattern: pattern,
            contentId: entry.parentMetaId,
            contentType: entry.parentMetaType,
            shape: PosterShape.poster
        )
    }

    private static let writeQueue = DispatchQueue(label: "TopShelfUpdater.write", qos: .utility)

    private static func roundedForComparison(_ item: TopShelfItemSnapshot) -> TopShelfItemSnapshot {
        TopShelfItemSnapshot(
            videoId: item.videoId, parentMetaId: item.parentMetaId, parentMetaType: item.parentMetaType,
            title: item.title, episodeTitle: item.episodeTitle, season: item.season, episode: item.episode,
            poster: item.poster, background: item.background,
            progressPercent: item.progressPercent.map { $0.rounded() }
        )
    }
}
