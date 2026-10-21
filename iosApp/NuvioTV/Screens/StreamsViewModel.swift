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

    /// Full re-fetch — used when a debrid resolve reports the picked link went stale
    /// (mobile shows the same "Refreshing results" toast and reloads). Uses the repository's
    /// reload() so the addon fetch carries forceRefresh=true and bypasses the HTTP cache —
    /// a stale-link retry that re-reads a cached stream list would just re-pick the dead link.
    func reload(forceManual: Bool = true) {
        lastState = nil
        StreamsRepository.shared.clear()
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

        let next: [Group] = state.groups.compactMap { group in
            let playable = group.streams.filter { Self.isListable(stream: $0, debridEnabled: debridEnabled) }
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
        let first = next.first?.rowKeys.first
        if firstRowKey != first { firstRowKey = first }

        var reason: String?
        var hint: String?
        if next.isEmpty && !loading {
            // The shared repository's `emptyStateReason` only covers "we truly found nothing"
            // (no addons, fetch failed, etc.) — it has no concept of the local playability
            // filter above, so a title with plenty of raw torrent results but no debrid
            // connection still reports `NoStreamsFound`-adjacent nils here. Detect that case
            // ourselves: shared handed us streams, but every one of them got filtered out.
            let rawCount = state.groups.reduce(0) { $0 + $1.streams.count }
            if rawCount > 0 {
                (reason, hint) = Self.describeFiltered(rawCount: rawCount, debridEnabled: debridEnabled)
            } else {
                (reason, hint) = Self.describe(state.emptyStateReason)
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

// MARK: - Row model (W3-16)

/// What shapes a prebuilt stream row beyond the stream itself: the shared badge settings and the
/// "- <Provider> Instant" suffix. Part of the row model's identity (`StreamRowModel.==` compares
/// the values it produced), and of `StreamsViewModel.Group`, so a settings flip rebuilds the rows.
nonisolated struct StreamRowDisplay: Equatable {
    /// The file-size chip is on (`showFileSizeBadges`; the row still needs a size to show it).
    var showFileSize = true
    /// Badges above the title instead of below it.
    var badgesOnTop = false
    /// The add-on column (logo + name) on the row's trailing edge.
    var showAddonLogo = false
    /// The Instant suffix on debrid-cached rows (debrid resolution on, no custom name template).
    var instantSuffix = false
}

/// An external player the row's long-press menu can offer. A plain-Swift copy of the Kotlin
/// `ExternalPlayerApp`, so the menu's list takes part in `StreamRowModel.==`.
nonisolated struct StreamRowPlayer: Equatable {
    let id: String
    let name: String
}

/// W3-16 (F1/F4, BUG-207): everything a stream row shows, as one plain value. Built in two steps:
///
/// - `make(stream:key:display:)`, once per stream in `StreamsViewModel.apply(_:)`: the focus key,
///   the title (with the Instant suffix), the description, the badges, the size, the add-on column,
///   the YouTube flag and the playback key (one SHA-256 pair, so a row body never recomputes it);
/// - `applying(...)`, in the picker's body: the four things only the picker knows — the debrid
///   spinner, the "Failed recently" caption, and the external players with their default.
///
/// `StreamRowView` is `Equatable` over this value, so a row whose model is unchanged is never
/// re-evaluated when a sibling's focus, the scroll or the list's state moves. Every field below is
/// compared: dropping one would freeze that part of a row (the spinner, the rejected caption, the
/// badge settings, the Instant-suffix title, the player list with its default).
nonisolated struct StreamRowModel: Equatable, Identifiable {
    /// The focus key (`"<groupId>#<identity>"`), stable across republishes.
    let key: String
    /// The row title, with the "- <Provider> Instant" suffix on a debrid-cached torrent row.
    let title: String
    /// The add-on's description (release name), nil when empty or absent.
    let description: String?
    let badges: [StreamBadgeInfo]
    /// The file-size chip's bytes; nil when the chip is off or the stream has no size.
    let sizeBytes: Int64?
    let badgesOnTop: Bool
    /// The add-on column (logo + name) is drawn.
    let showsAddonColumn: Bool
    let addonName: String
    /// The add-on's logo URL, nil when it has none.
    let addonLogo: String?
    /// The add-on gave only a YouTube video id: the row says so and resolves it on the device.
    let isYouTube: Bool
    /// `StreamItem.playbackStreamKey`: what `RejectedStreamLinks` stores.
    let playbackKey: String

    /// This row's debrid / YouTube resolve is in flight (the spinner beside the title).
    var isResolving = false
    /// The link failed recently for this title ("Failed recently" caption).
    var failedRecently = false
    /// The external players the long-press menu offers (empty = no menu).
    var players: [StreamRowPlayer] = []
    /// The validated default external player's id, nil when the built-in player is the default.
    var defaultPlayerId: String?

    var id: String { key }

    /// A size chip and/or badges are drawn.
    var hasBadgeRow: Bool { !badges.isEmpty || sizeBytes != nil }

    /// The part the picker's own state decides (spinner, rejected caption, players).
    func applying(isResolving: Bool, failedRecently: Bool, players: [StreamRowPlayer],
                  defaultPlayerId: String?) -> StreamRowModel {
        var copy = self
        copy.isResolving = isResolving
        copy.failedRecently = failedRecently
        copy.players = players
        copy.defaultPlayerId = defaultPlayerId
        return copy
    }

    /// Builds the static part of a row. `providerLabel` names the debrid provider for the Instant
    /// suffix (injected so a test needs no provider catalog).
    @MainActor
    static func make(
        stream: StreamItem,
        key: String,
        display: StreamRowDisplay,
        providerLabel: (StreamDebridCacheStatus) -> String = StreamRowModel.debridProviderLabel
    ) -> StreamRowModel {
        // Kotlin nullable Strings surface as non-optional Swift String, so widen explicitly.
        let desc: String? = stream.description_
        let rawSize: Int64? = stream.behaviorHints.videoSize?.int64Value
        let logo: String? = stream.addonLogo
        let badges: [StreamBadge] = stream.badges
        return StreamRowModel(
            key: key,
            title: title(for: stream, instantSuffix: display.instantSuffix, providerLabel: providerLabel),
            description: (desc ?? "").isEmpty ? nil : desc,
            badges: badges.map { StreamBadgeInfo($0) },
            sizeBytes: display.showFileSize ? rawSize : nil,
            badgesOnTop: display.badgesOnTop,
            showsAddonColumn: display.showAddonLogo,
            addonName: stream.addonName,
            addonLogo: (logo ?? "").isEmpty ? nil : logo,
            isYouTube: StreamPickerView.isYouTubeResolved(stream),
            playbackKey: stream.playbackStreamKey
        )
    }

    /// Row title with the mobile "- <Provider> Instant" suffix on debrid-cached torrent rows
    /// (`StreamCard.kt:instantServiceLabel`), shown only while debrid resolution is enabled and
    /// no custom stream-name template is active (`instantSuffix`).
    @MainActor
    static func title(
        for stream: StreamItem,
        instantSuffix: Bool,
        providerLabel: (StreamDebridCacheStatus) -> String = StreamRowModel.debridProviderLabel
    ) -> String {
        let base = stream.streamLabel
        guard instantSuffix,
              let status = stream.debridCacheStatus,
              status.state == .cached else { return base }
        let provider = providerLabel(status)
        return provider.isEmpty ? base : String(localized: "\(base) - \(provider) Instant")
    }

    /// The provider's short name, else the cache status' own name, else the provider's display name.
    static func debridProviderLabel(_ status: StreamDebridCacheStatus) -> String {
        var provider = DebridProviders.shared.shortName(id: status.providerId)
        if provider.trimmingCharacters(in: .whitespaces).isEmpty {
            provider = status.providerName.trimmingCharacters(in: .whitespaces)
        }
        if provider.isEmpty {
            provider = DebridProviders.shared.displayName(id: status.providerId)
        }
        return provider
    }
}
