import Combine
import Foundation
import SharedCore

/// Resolves and observes playable streams for a title via the shared `StreamsRepository`.
///
/// `load(type:videoId:...)` kicks off resolution across installed streaming addons; `uiState`
/// (`StateFlow<StreamsUiState>`) emits `groups` of `StreamItem`s as each addon responds.
///
/// A stream is surfaced when it either carries a direct HTTP(S) URL, or is a debrid candidate
/// (torrent/`clientResolve` result from an installed addon) while in-app debrid resolution is
/// enabled — those resolve to a direct link at click time in `StreamPickerView` (mobile parity:
/// `StreamsScreen.kt` / `App.kt` click paths). Also observes the shared badge + debrid settings
/// so the picker can render badge packs, file-size chips, placement, addon logos and the
/// "Instant" cached suffix exactly like mobile's `StreamCard`.
///
/// Empty state: `emptyReason` also covers the case where the shared repository found streams
/// but the local playability filter above dropped every one of them (torrent-only results with
/// debrid resolution off) — a different, actionable message from the shared "no streams found
/// at all" reasons, with `emptyReasonHint` pointing at the fix.
@MainActor
final class StreamsViewModel: ObservableObject {
    /// One playable, addon-grouped section for the picker UI. `Equatable` (the Kotlin streams
    /// compare by their data-class `equals`), so `apply(_:)` can skip an identical republish.
    struct Group: Identifiable, Equatable {
        let id: String           // addonId
        let addonName: String
        let streams: [StreamItem]
        /// One stable row key per stream, parallel to `streams` (see `rowKeys(groupId:streams:)`).
        let rowKeys: [String]
        /// W3-16 (F4): one prebuilt row model per stream, parallel to `streams` and `rowKeys`: built
        /// once in `apply(_:)` (keys, titles, badges, the playback key), never in the picker's body.
        let rows: [StreamRowModel]
        /// The display settings `rows` were built with (badge settings, Instant suffix); a change
        /// rebuilds the rows.
        let display: StreamRowDisplay
        /// Mirrors the shared `AddonStreamGroup.isLoading` — this addon hasn't finished
        /// responding yet (more streams may still arrive). Drives the per-group header spinner.
        let isLoading: Bool

        /// The same group with a new loading flag (rows and keys are reused as built).
        func withLoading(_ loading: Bool) -> Group {
            Group(id: id, addonName: addonName, streams: streams, rowKeys: rowKeys, rows: rows,
                  display: display, isLoading: loading)
        }
    }

    @Published private(set) var groups: [Group] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var emptyReason: String?
    /// Secondary guidance line for `emptyReason` — where to go fix it (e.g. which Settings
    /// section). Nil for the plain "nothing found" reasons, which have nothing actionable to add.
    @Published private(set) var emptyReasonHint: String?
    /// Focus key of the first stream row; the picker moves initial focus here when rows arrive.
    @Published private(set) var firstRowKey: String?
    /// Shared badge settings (imported packs, file-size toggle, placement, addon logo).
    @Published private(set) var badgeSettings: StreamBadgeSettingsUiState?
    /// Whether in-app debrid can resolve torrent results (drives filtering + "Instant" suffix).
    @Published private(set) var debridResolveEnabled = false
    /// Mobile parity (`StreamsScreen.kt:229`): append "- <Provider> Instant" to cached rows
    /// only when debrid resolution is on and no custom stream-name template is active.
    @Published private(set) var instantSuffixEnabled = false
    /// Non-nil when the active resolver's stored credential has failed auth (401/403) on a
    /// recent provider call — the BUG-21 failure mode where "Connected" was a lie. Rendered as
    /// a warning banner above the stream list; clears itself on the next successful call or
    /// when the user reconnects (the shared health object is the source of truth).
    @Published private(set) var credentialWarning: String?
    /// The shared repository's auto-play fields for the current request (orivio batch item 1),
    /// read by the picker's `FirstPlayAutoPlayController`. Unfiltered: the playability filter in
    /// `apply(_:)` shapes the visible list only. Republished only when a field actually changes.
    @Published private(set) var autoPlayFeed = FirstPlayAutoPlayFeed.empty
    /// Stream picker A (P1): how far the fan-out is, for the info panel's progress line. Counts the
    /// shared groups (one per add-on asked, listable or not) and the listable sources.
    @Published private(set) var fanOut = StreamFanOutProgress()
    /// Stream picker A (P2): one chip per add-on of the fan-out, in the shared group order, with
    /// its listable count and fetch state. Every add-on asked, not only the listable ones.
    @Published private(set) var sourceChips: [SourceChip] = []
    /// Stream picker A (P2): the shared per-add-on filter (`StreamsUiState.selectedFilter`); nil is
    /// "All". `groups` is already filtered by it.
    @Published private(set) var selectedFilter: String?

    private var watcher: FlowWatcher?
    private var badgeWatcher: FlowWatcher?
    private var debridWatcher: FlowWatcher?
    private var healthWatcher: FlowWatcher?
    /// Latest auth-failed provider ids from `DebridCredentialHealth`, kept to re-derive the
    /// warning when the active resolver changes (and vice versa).
    private var authFailedProviderIds: Set<String> = []
    private var activeResolverProviderId: String?
    /// Last raw state, kept so a debrid-settings flip re-filters without a reload.
    private var lastState: StreamsUiState?
    private let type: String
    private let videoId: String
    private let parentMetaId: String?
    private let season: KotlinInt?
    private let episode: KotlinInt?

    init(type: String, videoId: String, parentMetaId: String? = nil, season: Int? = nil, episode: Int? = nil) {
        self.type = type
        self.videoId = videoId
        self.parentMetaId = parentMetaId
        self.season = season.map { KotlinInt(int: Int32($0)) }
        self.episode = episode.map { KotlinInt(int: Int32($0)) }
    }

    // MARK: - Derived badge-setting conveniences (defaults mirror the shared repository)

    var showFileSizeBadges: Bool { badgeSettings?.showFileSizeBadges ?? true }
    /// Stream picker A (P1): the backdrop mode; the platform default (Cinematic on tvOS, decision
    /// D1) until the settings watcher has emitted.
    var backgroundMode: StreamBackgroundMode {
        badgeSettings?.backgroundMode ?? StreamBackgroundDefaults.shared.platformDefault
    }
    var showAddonLogo: Bool { badgeSettings?.showAddonLogo ?? false }
    var badgesOnTop: Bool { badgeSettings?.badgePlacement == .top }

    /// What shapes a prebuilt row (W3-16 F4): the badge settings plus the Instant suffix.
    private var rowDisplay: StreamRowDisplay {
        StreamRowDisplay(showFileSize: showFileSizeBadges, badgesOnTop: badgesOnTop,
                         showAddonLogo: showAddonLogo, instantSuffix: instantSuffixEnabled)
    }

    /// The display settings the current `groups` were built with.
    private var appliedDisplay = StreamRowDisplay()

    /// Row keys keyed by the stream's identity, not its position: add-ons stream in and the
    /// shared sort reorders, and a positional key moved focus and the resolve spinner onto a
    /// different stream. The identity is the add-on's own text plus the torrent hash, NOT the URL:
    /// debrid preparation swaps in a resolved URL while the picker is open (`replacePreparedStream`),
    /// and a URL-based key (`playbackStreamKey`) rebuilt the row and dropped its focus (review r1
    /// P2). Duplicates get a `~n` suffix; a stream with no identity falls back to its index. Keys
    /// keep the `"<groupId>#"` prefix the picker's collapse logic matches on. One SHA-256 per
    /// stream per `apply()`.
    static func rowKeys(groupId: String, streams: [StreamItem]) -> [String] {
        var seen: [String: Int] = [:]
        return streams.enumerated().map { index, stream in
            let identity = rowIdentity(stream)
            let base = identity.isEmpty ? "i\(index)" : identity
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return n == 0 ? "\(groupId)#\(base)" : "\(groupId)#\(base)~\(n)"
        }
    }

    private static func rowIdentity(_ stream: StreamItem) -> String {
        let name: String = stream.name ?? ""
        let title: String = stream.title ?? ""
        let description: String = stream.description_ ?? ""
        let hash: String = stream.infoHash ?? stream.clientResolve?.infoHash ?? ""
        let fileIdx = stream.fileIdx.map { "\($0.intValue)" } ?? ""
        let text = [name, title, description, hash, fileIdx].joined(separator: "\u{1F}")
        guard !text.allSatisfy({ $0 == "\u{1F}" }) else { return "" }
        return PlaybackStreamKey.digestHex(text, bytes: 12)
    }

    /// `forceManual` false lets the shared repository run its direct auto-play flow for this load
    /// (`manualSelection: false`); the picker passes false only while first-play auto mode is armed.
    func start(forceManual: Bool = true) {
        guard watcher == nil else { return }

        StreamBadgeSettingsRepository.shared.ensureLoaded()
        DebridSettingsRepository.shared.ensureLoaded()

        watcher = FlowWatcherKt.watch(StreamsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? StreamsUiState else { return }
            self.lastState = state
            self.apply(state)
        }
        badgeWatcher = FlowWatcherKt.watch(StreamBadgeSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let value = emitted as? StreamBadgeSettingsUiState else { return }
            self.badgeSettings = value
            // The prebuilt rows carry these settings (W3-16 F4): rebuild only if they moved.
            self.reapplyIfDisplayChanged()
        }
        debridWatcher = FlowWatcherKt.watch(DebridSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let value = emitted as? DebridSettings else { return }
            let canResolve = value.canResolvePlayableLinks
            let instant = canResolve && !value.hasCustomStreamFormatting
            if self.instantSuffixEnabled != instant { self.instantSuffixEnabled = instant }
            self.activeResolverProviderId = canResolve ? value.activeResolverProviderId : nil
            self.updateCredentialWarning()
            if self.debridResolveEnabled != canResolve {
                self.debridResolveEnabled = canResolve
                // Filtering depends on this flag — re-derive the visible groups.
                if let last = self.lastState { self.apply(last) }
            } else {
                self.reapplyIfDisplayChanged()
            }
        }
        healthWatcher = FlowWatcherKt.watch(DebridCredentialHealth.shared.authFailedProviderIds) { [weak self] emitted in
            guard let self else { return }
            // Kotlin Set<String> arrives as a Swift Set of AnyHashable.
            let ids = (emitted as? Set<AnyHashable>)?.compactMap { $0 as? String } ?? []
            self.authFailedProviderIds = Set(ids)
            self.updateCredentialWarning()
        }

        // BUG-74: the id this screen was actually handed, logged before the fetch so a tester's
        // photo shows it even if the fetch then reports nothing at all.
        StreamProbe.log("open type=\(type) id=\(videoId)"
            + (season.map { " s=\($0)" } ?? "")
            + (episode.map { " e=\($0)" } ?? ""))

        StreamsRepository.shared.load(
            type: type,
            videoId: videoId,
            parentMetaId: parentMetaId,
            season: season,
            episode: episode,
            manualSelection: forceManual
        )
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        badgeWatcher?.cancel()
        badgeWatcher = nil
        debridWatcher?.cancel()
        debridWatcher = nil
        healthWatcher?.cancel()
        healthWatcher = nil
        StreamsRepository.shared.clear()
    }

    /// Rebuilds `credentialWarning` from the latest health set + active resolver. Only the
    /// ACTIVE resolver's failure is surfaced here — a stale key on a non-active provider
    /// doesn't affect this screen and is handled by the Settings pane instead.
    private func updateCredentialWarning() {
        guard let providerId = activeResolverProviderId,
              authFailedProviderIds.contains(providerId) else {
            credentialWarning = nil
            return
        }
        let name = DebridProviders.shared.displayName(id: providerId)
        credentialWarning = String(
            localized: "Your \(name) session has expired. Reconnect in Settings \u{2192} Services \u{2192} Debrid."
        )
    }

    /// Stream picker A (P2): select a source chip; nil is "All". The repository republishes and
    /// `apply(_:)` rebuilds `groups` from the filtered groups.
    func selectFilter(_ addonId: String?) {
        StreamsRepository.shared.selectFilter(addonId: addonId)
    }

    /// Full re-fetch — the refresh chip (P2), and the stale-link path (a debrid resolve reports
    /// the picked link went stale; mobile shows the same "Refreshing results" toast and reloads).
    /// Uses the repository's reload() so the addon fetch carries forceRefresh=true and bypasses
    /// the HTTP cache — a stale-link retry that re-reads a cached stream list would just re-pick
    /// the dead link. No `clear()` first (P0.1 / P2): the repository starts the same request
    /// token afresh itself, and that is what lets the selected source chip survive the refresh
    /// (`StreamFilterRetention`); a `clear()` emptied the token and reset the chip to "All".
    func reload(forceManual: Bool = true) {
        lastState = nil
        StreamsRepository.shared.reload(
            type: type,
            videoId: videoId,
            parentMetaId: parentMetaId,
            season: season,
            episode: episode,
            manualSelection: forceManual
        )
    }

    /// Re-derives the groups when only the row display settings moved (badge settings, Instant
    /// suffix) since the last `apply(_:)`; a no-op before the first emission or when they are equal.
    private func reapplyIfDisplayChanged() {
        guard let last = lastState, rowDisplay != appliedDisplay else { return }
        apply(last)
    }

    /// Publishes `state` to the picker. W3-16 (F4): the rows (keys included) are built here, once per
    /// stream — a group whose streams, name and display settings are unchanged since the last call
    /// is reused as built (no SHA for its keys, no Kotlin bridging for its titles) — and a result
    /// identical to what is already published is not republished at all: every `@Published` write
    /// below is guarded, because an equal write still invalidates the picker's body.
    func apply(_ state: StreamsUiState) {
        let loading = state.isAnyLoading
        if isLoading != loading { isLoading = loading }
        let debridEnabled = debridResolveEnabled
        let display = rowDisplay
        appliedDisplay = display

        var previous: [String: Group] = [:]
        for group in groups where previous[group.id] == nil { previous[group.id] = group }

        // P2: every add-on of the fan-out with its listable streams, computed ONCE per group (W3-16's
        // budget: `isListable` is three Kotlin bridge reads per stream). The chips see every add-on;
        // the list sees only the selected one (`selectedFilter`), or all of them.
        let filter: String? = state.selectedFilter
        let listed: [(group: AddonStreamGroup, playable: [StreamItem])] = state.groups.map { group in
            (group, group.streams.filter { Self.isListable(stream: $0, debridEnabled: debridEnabled) })
        }
        let chips: [SourceChip] = listed.map { entry in
            SourceChip(
                id: entry.group.addonId,
                name: entry.group.addonName,
                count: entry.playable.count,
                isLoading: entry.group.isLoading,
                error: { let e: String? = entry.group.error; return (e ?? "").isEmpty ? nil : e }()
            )
        }
        if chips != sourceChips { sourceChips = chips }
        if filter != selectedFilter { selectedFilter = filter }

        let next: [Group] = listed.compactMap { entry in
            let group = entry.group
            guard filter == nil || group.addonId == filter else { return nil }
            let playable = entry.playable
            guard !playable.isEmpty else { return nil }
            if let old = previous[group.addonId], old.display == display,
               old.addonName == group.addonName, old.streams == playable {
                return old.withLoading(group.isLoading)
            }
            let keys = Self.rowKeys(groupId: group.addonId, streams: playable)
            let rows = zip(keys, playable).map { key, stream in
                StreamRowModel.make(stream: stream, key: key, display: display)
            }
            return Group(id: group.addonId, addonName: group.addonName, streams: playable,
                         rowKeys: keys, rows: rows, display: display, isLoading: group.isLoading)
        }
        if next != groups { groups = next }
        // The info pane's progress counts the whole fan-out, whatever chip is selected.
        let progress = StreamFanOutProgress(
            answered: state.groups.filter { !$0.isLoading }.count,
            expected: state.groups.count,
            sources: chips.reduce(0) { $0 + $1.count },
            addonsWithSources: chips.filter { $0.count > 0 }.count,
            isLoading: loading,
            hasOutcome: !state.groups.isEmpty || state.emptyStateReason != nil
        )
        if progress != fanOut { fanOut = progress }
        let first = next.first?.rowKeys.first
        if firstRowKey != first { firstRowKey = first }

        var reason: String?
        var hint: String?
        // `hasOutcome` (review r2): a reload first emits an empty, non-loading state for a frame;
        // no reason for that one, it is not a verdict.
        if next.isEmpty && !loading && progress.hasOutcome {
            if let filter, let chip = chips.first(where: { $0.id == filter }) {
                // P2 (review r1): one add-on is selected and it has nothing listable: say so about
                // THAT add-on, never the whole fan-out's counts or debrid hints.
                (reason, hint) = Self.describeFilteredSource(chip)
            } else {
                // The shared repository's `emptyStateReason` only covers "we truly found nothing"
                // (no addons, fetch failed, etc.) — it has no concept of the local playability
                // filter above, so a title with plenty of raw torrent results but no debrid
                // connection still reports `NoStreamsFound`-adjacent nils here. Detect that case
                // ourselves: shared handed us streams, but every one of them got filtered out.
                let rawCount = state.filteredGroups.reduce(0) { $0 + $1.streams.count }
                if rawCount > 0 {
                    (reason, hint) = Self.describeFiltered(rawCount: rawCount, debridEnabled: debridEnabled)
                } else {
                    (reason, hint) = Self.describe(state.emptyStateReason)
                }
            }
        }
        if emptyReason != reason { emptyReason = reason }
        if emptyReasonHint != hint { emptyReasonHint = hint }

        // Last, so a controller reacting to it (`.onReceive`) already sees this state's list.
        // Never the overlay flag (`showDirectAutoPlayOverlay`): the tmdb→IMDb remap briefly
        // publishes a state with it off mid-flow. The controller reads the flow fields instead.
        let token: String? = state.requestToken
        let autoStream: StreamItem? = state.autoPlayStream
        let feed = FirstPlayAutoPlayFeed(
            requestToken: token,
            autoPlayStream: autoStream,
            autoPlayCandidates: state.autoPlayCandidates,
            isDirectAutoPlayFlow: state.isDirectAutoPlayFlow,
            isAnyLoading: state.isAnyLoading,
            hasOutcome: !state.groups.isEmpty || state.emptyStateReason != nil
        )
        if feed != autoPlayFeed { autoPlayFeed = feed }
    }

    /// Whether the picker lists `stream` at all: it has a direct link, it is a torrent /
    /// clientResolve result from an installed add-on that the in-app debrid connection resolves at
    /// click time (`DirectDebridPlaybackResolver`), or (batch D U2, upstream 94976222) its only
    /// playable field is a YouTube video id, which `StreamPickerView` resolves on the device when
    /// the row is picked. Note the first-play auto-start never sees a ytId-only stream: the shared
    /// `autoPlayCandidates` selector and `FirstPlayAutoPlayController` walk only direct links and
    /// debrid candidates, which excludes it on purpose (the resolve costs seconds and its link
    /// expires within hours).
    static func isListable(stream: StreamItem, debridEnabled: Bool) -> Bool {
        // Widen through an explicit String? — Kotlin's nullable String surfaces here as a
        // non-optional Swift String, so direct optional-chaining/binding won't compile.
        let direct: String? = stream.playableDirectUrl
        if !(direct ?? "").isEmpty { return true }
        if debridEnabled && stream.isAddonDebridCandidate { return true }
        let youTubeId: String? = stream.youTubeIdToResolve
        return !(youTubeId ?? "").isEmpty
    }

    /// Builds the reason/hint pair for the "shared found streams, but our playability filter
    /// dropped all of them" case. Distinguishes the common cause (debrid off, torrent-only
    /// results) from the rarer one (debrid already on, but nothing still resolved) so the hint
    /// never tells someone to do something they've already done.
    private static func describeFiltered(rawCount: Int, debridEnabled: Bool) -> (String, String?) {
        let sourceWord = rawCount == 1 ? "source" : "sources"
        if !debridEnabled {
            let reason = String(localized: "Found \(rawCount) torrent \(sourceWord), but no debrid service is connected.")
            let hint = String(localized: "Connect one in Settings \u{2192} Services \u{2192} Debrid, or turn on \u{201C}Resolve Streams with Debrid\u{201D}.")
            return (reason, hint)
        }
        let reason = String(localized: "Found \(rawCount) \(rawCount == 1 ? "stream" : "streams"), but none could be resolved to a playable link.")
        return (reason, nil)
    }

    /// P2: the empty state for one selected add-on: its failure (the shared `error` as the hint),
    /// or simply nothing playable from it.
    static func describeFilteredSource(_ chip: SourceChip) -> (String, String?) {
        if let error = chip.error, !error.isEmpty {
            return (String(localized: "\(chip.name) couldn\u{2019}t be reached."), error)
        }
        return (String(localized: "\(chip.name) returned no playable sources."), nil)
    }

    /// BUG-74: `NoCompatibleAddons` used to assert "only a metadata catalog (Cinemeta) is set up",
    /// which was a guess dressed as a fact — and when a `tmdb:` id filtered out addons the user
    /// definitely had installed, it was a confident lie that sent them looking in the wrong place
    /// for three weeks. Both strings now describe what we actually know, and the id case has its
    /// own reason so it can say so.
    private static func describe(_ reason: StreamsEmptyStateReason?) -> (String, String?) {
        switch reason?.name {
        case "NoAddonsInstalled":
            return (String(localized: "No addons installed."),
                    String(localized: "Add one in the Add-ons tab."))
        case "NoCompatibleAddons":
            return (String(localized: "None of your addons provide streams for this title."),
                    String(localized: "Your installed addons either don\u{2019}t serve streams, or don\u{2019}t cover this content type."))
        case "IncompatibleContentId":
            return (String(localized: "Couldn\u{2019}t look this title up with your stream addons."),
                    String(localized: "It was opened from a TMDB source and has no matching IMDb id, which is what stream addons need. Opening it from search or a different row usually works."))
        case "NoStreamsFound":
            return (String(localized: "No streams found for this title."), nil)
        case "StreamFetchFailed":
            return (String(localized: "Stream lookup failed."), nil)
        default:
            return (String(localized: "No playable streams. Install a streaming addon, or connect a debrid account in Settings \u{2192} Services \u{2192} Debrid to play torrent results."), nil)
        }
    }

    deinit {
        watcher?.cancel()
        badgeWatcher?.cancel()
        debridWatcher?.cancel()
        healthWatcher?.cancel()
    }
}

// MARK: - Fan-out progress (stream picker A, P1)

/// What the info panel's progress line reads: add-ons answered of add-ons asked, the listable
/// source count, and whether anything is still loading. Equatable so an unchanged value is not
/// republished.
nonisolated struct StreamFanOutProgress: Equatable {
    /// Add-ons that have answered (with or without sources).
    var answered = 0
    /// Add-ons asked in this fan-out (one shared group each).
    var expected = 0
    /// Listable sources across every answered add-on.
    var sources = 0
    /// Add-ons that returned at least one listable source (the "from N add-ons" count).
    var addonsWithSources = 0
    var isLoading = false
    /// The shared repository has said something for this request (groups or an empty-state
    /// reason). False before the first emission, when nothing is known yet (review r1 P3).
    var hasOutcome = false
}
