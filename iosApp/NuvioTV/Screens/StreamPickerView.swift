import SwiftUI
import SharedCore

/// Presented when the user taps Play. Resolves streams for the title, lists the playable ones
/// grouped by addon, and opens the native player on selection.
///
/// Debrid: torrent/`clientResolve` results from installed addons (no direct URL) are listed when
/// in-app debrid resolution is enabled, and resolve to a direct link at click time through the
/// shared `DirectDebridPlaybackResolver` (mobile parity: `App.kt:2157`, `StreamsScreen.kt:363`).
/// Failures surface as a transient toast using the same wording as the shared `toastMessage()`.
///
/// Badges: rows render imported badge-pack chips, the file-size chip, TOP/BOTTOM placement, the
/// optional addon logo and the "- <Provider> Instant" cached suffix (mobile `StreamCard` parity).
///
/// Grouping: each addon's streams sit under a collapsed-by-default, focusable header (name,
/// stream count, per-addon loading spinner). Rows only build while their group is expanded — a
/// `LazyVStack` throughout — so the picker no longer lags while addons are still resolving
/// (previously every addon's rows were built eagerly in one long always-expanded list). A lone
/// addon auto-expands; anything past that stays collapsed until picked, and never
/// auto-collapses/re-expands as later addons stream in.
///
/// Focus: rows and group headers carry stable focus keys. Initial focus lands on the first
/// stream row when there's a single, auto-expanded group, otherwise on the first group's header.
/// Collapsing a group that holds focus retargets focus to that group's header first. (Previously
/// the dev test-stream button at the bottom was the only focusable view while loading, so focus
/// landed — and stayed — at the bottom of the list.)
///
/// Auto-Play Best Source (orivio batch item 1): with the "first stream" auto-play mode on and the
/// picker not forced manual, a visit opens in auto mode — `FirstPlayAutoPlayController` walks the
/// shared repository's settled candidates under a full-screen "Finding the best source…" overlay
/// and opens the player itself; Back from that player dismisses the picker too. With an external
/// default player (Settings → Player → Default Player) the first auto pick is handed to it and
/// the picker closes; failover always plays in the built-in player. Menu on the overlay
/// drops to the list. Failover (item 2): a presented playback that fails is remembered
/// (`RejectedStreamLinks`) and, by `PlaybackContext.launchSource`, swaps in the next auto
/// candidate, opens a picker for the Up Next episode that failed, or offers "Try Next Source".
struct StreamPickerView: View {
    let type: String
    let videoId: String
    let title: String

    let parentMetaId: String
    let season: Int?
    let episode: Int?
    /// All episodes of the parent series (from `MetaDetails.videos`); enables next-episode
    /// autoplay in the player. Empty for movies or launch paths without the series meta.
    let episodes: [MetaVideo]
    /// Info-tab header inputs (optional; launch paths without meta at hand pass nil and the header
    /// omits them). `poster` is the catalog/series poster (also persisted as the parent artwork by
    /// the progress recorder); `episodeStill` is the 16:9 episode image shown in preference to it.
    let poster: String?
    let episodeStill: String?
    let synopsis: String?
    /// Title-level facts for the player's Info tab chips (nil when the caller has no meta).
    let meta: PlaybackMeta?
    /// FEAT-42: the title's configured logo (series/movie `MetaDetails.logo`), shown in place of
    /// the plain text heading when it loads — mobile parity for the stream picker screen. `nil`
    /// on launch paths with no meta at hand (Home continue-watching, Top Shelf).
    let logoUrl: String?
    /// Never auto-start, whatever the auto-play setting says ("Choose Source…", "Play Manually").
    let forceManual: Bool
    /// "Start Over": every playback this picker starts ignores saved progress.
    let startFromBeginning: Bool
    /// A toast shown when the picker opens on its list (the Up Next failover picker's explanation).
    let notice: String?
    /// P5 B22: set by presenters that push a Detail page once the picker closes; forwarded to the
    /// player's post-play More Like This row.
    let onOpenTitle: ((MetaPreview) -> Void)?

    @StateObject private var model: StreamsViewModel
    @StateObject private var autoPlay: FirstPlayAutoPlayController
    /// First-play auto mode for this visit. BUG-183 (Steven rc7): decided in `init` (a synchronous
    /// settings read, like `PlayerLoadingOverlaySetting`), so the loading cover is up from the
    /// picker's first frame instead of after `onAppear` armed the controller (the list flashed for
    /// about a second). The controller itself is still armed once, at the first appearance. Cleared
    /// when the controller plays, gives up or is cancelled, so every later load — the debrid-Stale
    /// reload — asks for the plain list (`manualSelection`).
    @State private var autoPlayArmed: Bool
    @State private var autoPlayEvaluated = false
    /// BUG-174/183 (Steven rc7): the loading cover stays over the list — while an auto pick's player
    /// is being presented and up (the controller's `.done` alone hid it a beat too early), while
    /// the Up Next failover picker is up, and while the picker closes after a player (the list
    /// must not show on the way out).
    @State private var coverHold = false
    /// BUG-185 (Steven rc9, D6): the held cover is the close-time hold (the picker is leaving after
    /// a player or a hand-off), drawn as plain black: the title logo is for starts only.
    @State private var coverIsCloseHold = false
    /// BUG-185: when the viewer's close of the player reached the cover binding, for the
    /// setter → `onDismiss` timing line (under 100 ms reads as an instant dismiss).
    @State private var playerCloseRequestedAt: CFAbsoluteTime?
    /// BUG-174: the player closed onto something the viewer needs to see on the list (an auto walk
    /// that ended with nothing during a failover). Read once, by `handlePlayerDismissed`.
    @State private var keepListAfterPlayer = false
    /// Review r1 (P2): an external hand-off is waiting for the add-on subtitles (D5).
    @State private var externalHandOffInFlight = false
    /// Up Next failover: the picker for the episode whose source failed, presented once the player
    /// has closed (`pendingFailoverTarget` waits for that).
    @State private var failoverTarget: FailoverTarget?
    @State private var pendingFailoverTarget: FailoverTarget?
    /// Manual-pick failure alert, raised once the player has closed.
    @State private var manualFailureAlert: ManualFailureAlert?
    @State private var pendingManualFailureAlert: ManualFailureAlert?
    /// The list as it was when the viewer picked a row: "Try Next Source" walks this order.
    @State private var manualFailoverList: [StreamItem] = []
    /// Keys of links that failed recently for this title (row caption), re-read at the moments
    /// they can change — `RejectedStreamLinks` itself keeps no cache.
    @State private var rejectedKeys: Set<String> = []
    /// A "Start Over" playback from this picker has played five minutes: the request is honoured,
    /// so a later failover or retry resumes from the saved position instead of starting over again.
    @State private var startOverHonoured = false
    @State private var selected: PlaybackContext?
    /// Episodes fetched on demand when a series launch path didn't supply them (Home
    /// continue-watching, Detail's primary Play). Filled from `MetaDetailsRepository.fetch`
    /// (cache-first, side-effect free) so next-episode autoplay works from every path.
    @State private var fetchedEpisodes: [MetaVideo] = []
    /// Row key currently mid debrid-resolve (drives the row spinner; one resolve at a time).
    @State private var resolvingKey: String?
    /// False once the picker left the screen (a Menu press during a resolve): a late result must
    /// not hand a link to an external player from a view that is gone (batch D review r1).
    @State private var pickerOnScreen = false
    /// Batch D review r2 P3-2: the YouTube resolve in flight, by request. `resolvingKey == rowKey`
    /// was no guard at all (only the owning completion ever reset it), and `selected == nil`
    /// missed a playback that started AND ended inside the resolve window (an auto-play pick or
    /// a failover dismissed within the 30 s). The token is minted when a resolve starts and
    /// dropped the moment any playback starts (`selected` set, see `onChange`) or the picker
    /// leaves the screen; a completion whose token is no longer current does nothing.
    @State private var youTubeResolveToken: UUID?
    /// The resolve's Task (review r2 P3-3): cancelled with the token, so a superseded or abandoned
    /// resolve stops the extractor instead of running to the 30 s timeout in the background.
    @State private var youTubeResolveTask: Task<Void, Never>?
    /// Transient failure message (debrid resolve errors), auto-dismissed after a few seconds.
    @State private var toast: String?
    @FocusState private var focusedRow: String?
    /// Addon ids whose group is currently expanded. Collapsed (absent) by default; see
    /// `body`'s auto-expand-single-group handling and `toggleExpansion(_:)`.
    @State private var expandedGroups: Set<String> = []
    /// Guards the one-time auto-expand check so a second addon streaming in later never
    /// collapses/re-expands anything under the user (no layout shifts under focus).
    @State private var didAutoExpand = false
    /// External players installed on this Apple TV (FEAT-5). Probed once per appearance via the
    /// shared `ExternalPlayerPlatform` — `canOpenURL` only returns true for schemes declared in
    /// Info.plist's `LSApplicationQueriesSchemes` (Infuse, VLC, Outplayer, VidHub as of FEAT-21,
    /// SenPlayer as of FEAT-56),
    /// so testers without any of them installed never see the handoff option at all. Empty ⇒ no
    /// menu is attached.
    @State private var externalPlayers: [ExternalPlayerApp] = []
    /// User-chosen default player (Settings → Player → Default Player). Empty = built-in.
    /// Same device-local key `DefaultPlayerRow` writes; validated against the live probe below
    /// so an uninstalled default silently reverts to built-in instead of dead-ending playback.
    @AppStorage("default_external_player_id") private var defaultExternalPlayerId = ""
    @Environment(\.dismiss) private var dismiss

    private static let testRowKey = "test-stream"
    /// Spinner key for a "Try Next Source" resolve (its row may be collapsed or off-screen).
    private static let failoverRowKey = "failover-next"
    /// Spinner key while an external hand-off waits for the add-on subtitles (D5) with no row of
    /// its own (the auto path).
    private static let handOffRowKey = "external-handoff"
    /// `ExternalPlayerApp.id`s of the external players that report the stop position back over an
    /// x-callback return (`ExternalPlaybackReturn`): Infuse (7.6.2+, `x-success` with `position`)
    /// and, FEAT-56 (GitHub #5), SenPlayer (6.1.1+ returns the current playback time on exit; the
    /// query parameter name is unverified on hardware — the `debug.extPlayerProbe` print in
    /// `ContentView.handleDeepLink` shows what it sends). Every other player gets no callback URLs.
    static let returnReportingPlayerIds: Set<String> = ["infuse", "senplayer", "nativeplayer"]
    private let testStreamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!

    init(
        type: String,
        videoId: String,
        title: String,
        parentMetaId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodes: [MetaVideo] = [],
        poster: String? = nil,
        episodeStill: String? = nil,
        synopsis: String? = nil,
        meta: PlaybackMeta? = nil,
        logoUrl: String? = nil,
        forceManual: Bool = false,
        startFromBeginning: Bool = false,
        notice: String? = nil,
        onOpenTitle: ((MetaPreview) -> Void)? = nil
    ) {
        self.onOpenTitle = onOpenTitle
        self.meta = meta
        self.logoUrl = logoUrl
        self.forceManual = forceManual
        self.startFromBeginning = startFromBeginning
        self.notice = notice
        self.poster = poster
        self.episodeStill = episodeStill
        self.synopsis = synopsis
        self.type = type
        self.videoId = videoId
        self.title = title
        self.parentMetaId = parentMetaId ?? videoId
        self.season = season
        self.episode = episode
        self.episodes = episodes
        // BUG-183: decided here, not in `onAppear` — the cover must be in the first frame.
        _autoPlayArmed = State(initialValue: !forceManual && Self.firstStreamAutoPlayOn())
        _model = StateObject(wrappedValue: StreamsViewModel(
            type: type, videoId: videoId, parentMetaId: parentMetaId, season: season, episode: episode
        ))
        _autoPlay = StateObject(wrappedValue: FirstPlayAutoPlayController(
            titleKey: videoId,
            dependencies: .live(type: type, videoId: videoId, season: season, episode: episode)
        ))
    }

    /// `listedStream` is the stream as the list shows it (pre-resolve) and `streamKey` its
    /// `playbackStreamKey`; both empty for the test stream. "Start Over" carries over until a
    /// playback has honoured it (`startOverHonoured`).
    private func context(url: URL, stream: StreamItem?, listedStream: StreamItem? = nil, streamKey: String = "",
                         launchSource: PlaybackLaunchSource = .manual, attempt: Int = 0) -> PlaybackContext {
        PlaybackContext(
            url: url,
            title: title,
            contentType: type,
            parentMetaId: parentMetaId,
            videoId: videoId,
            season: season,
            episode: episode,
            poster: poster,
            background: nil,
            providerName: stream?.addonName,
            providerAddonId: stream?.addonId,
            streamTitle: stream.map { $0.streamLabel },
            streamSubtitle: { let s: String? = stream?.description_; return s }(),
            externalSubtitles: (stream?.externalSubtitles ?? []).map { sub in
                SubtitleFile(url: sub.url, language: sub.language, name: { let n: String? = sub.name; return n }())
            },
            bingeGroup: { let bg: String? = stream?.behaviorHints.bingeGroup; return bg }(),
            episodes: episodes.isEmpty ? fetchedEpisodes : episodes,
            synopsis: synopsis,
            episodeStill: episodeStill,
            logo: logoUrl,
            meta: meta,
            fileSizeBytes: { let n: Int64? = stream?.behaviorHints.videoSize?.int64Value; return n }(),
            streamAudioDelayMs: { let n: Int? = stream?.behaviorHints.audioDelayMs?.intValue; return n }(),
            requestHeaders: StreamModelsKt.sanitizePlaybackHeaders(
                headers: stream?.behaviorHints.proxyHeaders?.request),
            launchSource: launchSource,
            streamKey: streamKey,
            startFromBeginning: startsOver,
            attempt: attempt,
            listedStream: listedStream,
            // Batch D U2: a ytId-only stream plays a link resolved on this device that expires
            // within hours — never persisted as the entry's last source URL.
            sessionOnlySourceUrl: Self.isYouTubeResolved(listedStream)
        )
    }

    /// Series launch paths that don't carry the episode list (Home continue-watching, Detail's
    /// primary Play) get it fetched here so the player can offer next-episode autoplay. No-op for
    /// movies and for paths that already passed `episodes` (EpisodesSection).
    private func fetchEpisodesIfNeeded() {
        guard episodes.isEmpty, fetchedEpisodes.isEmpty,
              ["series", "tv", "show", "tvshow"].contains(type.lowercased()) else { return }
        // The `@Throws` twin: a Kotlin exception out of the plain suspend export aborts the process.
        Task { @MainActor in
            do {
                let details = try await MetaDetailsRepository.shared.fetchChecked(
                    type: type, id: parentMetaId, cacheResult: true
                )
                let videos = details?.videos ?? []
                guard !videos.isEmpty else { return }
                fetchedEpisodes = videos
            } catch {
                print("[StreamPicker] episode list fetch failed: \(error)")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Lazy so collapsed groups' rows (the overwhelming majority while addons are
                // still streaming in) are never built at all — this was the lag source (BUG-5):
                // a non-lazy VStack built every row of every addon up front.
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl - Theme.Spacing.xs) {
                    // FEAT-42: one heading — the title's logo when it loads, else the plain text
                    // title (mobile shows the series/movie logo on its stream-list screen too).
                    // beta.19-rc1 verdict (I1, BUG-134): the TMDB `original` logo, decoded for the header's slot.
                    TitleLogoHeader(title: title, logoUrl: logoUrl,
                                    decodeSize: .points(width: 600, height: 120), upgrade: .logo)

                    // BUG-21 follow-up: the active debrid credential failed auth on a recent
                    // call — without this banner the only symptom is every resolve failing
                    // while Settings still says "Connected". Not focusable; purely advisory.
                    if let warning = model.credentialWarning {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(warning)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        .padding(Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.yellow.opacity(0.12))
                        )
                        .frame(maxWidth: 1100, alignment: .leading)
                    }

                    if model.isLoading {
                        HStack(spacing: Theme.Spacing.md) {
                            ProgressView()
                            Text("Finding streams\u{2026}").foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }

                    ForEach(model.groups) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            groupHeader(group)
                            // Collapsed groups render nothing at all (not just off-screen —
                            // absent from the hierarchy), which is what actually kills the lag:
                            // the old always-expanded list built every row of every addon.
                            if expandedGroups.contains(group.id) {
                                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    ForEach(Array(zip(group.rowKeys, group.streams)), id: \.0) { key, stream in
                                        streamRow(stream, key: key)
                                    }
                                }
                                .padding(.top, Theme.Spacing.xs)
                            }
                        }
                        // Each addon group is its own focus section: D-pad up/down navigates
                        // between group headers and (when expanded) that group's rows without
                        // leaking focus into a sibling group's rows.
                        .focusSection()
                    }

                    if let reason = model.emptyReason {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            // Primary reason renders at full text-primary weight — prominent,
                            // not the muted secondary tone the plain "nothing found" empty
                            // states get elsewhere on tvOS — since the debrid/filtered case is
                            // actionable rather than a dead end.
                            Text(reason)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            if let hint = model.emptyReasonHint {
                                Text(hint)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }

                    // Dev/diagnostics affordance — only when there is nothing real to play, so it
                    // can never steal initial focus from the stream list (the old always-visible
                    // button was the only focusable view while loading → focus started at the
                    // bottom of the screen).
                    if model.groups.isEmpty && !model.isLoading {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Test")
                                .font(Theme.Font.sectionTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Button {
                                selected = context(url: testStreamURL, stream: nil)
                            } label: {
                                Label("Play test stream (Apple HLS sample)", systemImage: "play.circle")
                                    .padding(.vertical, Theme.Spacing.xs)
                            }
                            .buttonStyle(.glass)
                            .focused($focusedRow, equals: Self.testRowKey)
                        }
                        .padding(.top, Theme.Spacing.lg)
                    }
                }
                .padding(Theme.Spacing.screen)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Under the loading cover nothing in the list may take focus or a Select.
                .disabled(loadingCoverVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.background.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Surface.overlay, in: Capsule())
                        .padding(.bottom, Theme.Spacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                // BUG-182/183: the player's own loading look, no fade of its own (a swap to the
                // player's overlay must be invisible).
                if loadingCoverVisible { loadingCover }
            }
            .onReceive(model.$autoPlayFeed) { feed in autoPlay.ingest(feed) }
            .onReceive(autoPlay.events) { event in handleAutoPlayEvent(event) }
            .alert(
                "Couldn\u{2019}t play this source",
                isPresented: Binding(
                    get: { manualFailureAlert != nil },
                    set: { if !$0 { manualFailureAlert = nil } }
                ),
                presenting: manualFailureAlert
            ) { alert in
                if let retry = alert.retry, let engine = alert.retryEngine {
                    Button(engine == .mpv ? LocalizedStringKey("Try with mpv") : LocalizedStringKey("Try Native Player")) {
                        manualFailureAlert = nil
                        // The link is being retried on the other engine: it is not dead yet (a retry
                        // that works but closes before 300 s must not leave it flagged for 8 h).
                        RejectedStreamLinks.keep(retry.streamKey, title: retry.videoId)
                        rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selected = retry
                        }
                    }
                }
                if let next = alert.next {
                    Button("Try Next Source") {
                        manualFailureAlert = nil
                        // Let the alert finish dismissing before the player cover presents.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            internalPlay(next, rowKey: Self.failoverRowKey, attempt: alert.attempt)
                        }
                    }
                }
                Button("Back to Sources", role: .cancel) {
                    manualFailureAlert = nil
                }
            } message: { alert in
                Text(alert.reason)
            }
            .onChange(of: model.groups.map(\.id)) { _, ids in
                guard !ids.isEmpty else { return }
                // Auto-expand exactly once, only when the very first batch of groups turns out
                // to be a single addon. Never re-evaluated afterward, so a second addon
                // streaming in later doesn't retroactively collapse or expand anything.
                if !didAutoExpand {
                    didAutoExpand = true
                    if ids.count == 1 { expandedGroups = [ids[0]] }
                }

                // Move initial focus once groups (first) arrive: to the first stream row when
                // there's a single, auto-expanded group (unchanged from before collapsing was
                // added), otherwise to the first group's header. Never steals focus after the
                // user has moved it to a real row/header: only fires while focus is nowhere or
                // on the (now hidden) test button. Never while the auto-play overlay holds focus
                // (the list is disabled under it); `focusListAfterAutoPlay()` runs when it lifts.
                guard !loadingCoverVisible else { return }
                guard focusedRow == nil || focusedRow == Self.testRowKey else { return }
                if ids.count == 1, let firstKey = model.firstRowKey {
                    DispatchQueue.main.async { focusedRow = firstKey }
                } else if let firstId = ids.first {
                    DispatchQueue.main.async { focusedRow = Self.headerKey(groupId: firstId) }
                }
            }
            .onAppear {
                pickerOnScreen = true
                // Main-thread only (UIApplication.canOpenURL); cheap enough to re-probe every
                // appearance so an Infuse install mid-session is picked up next time the picker
                // opens instead of requiring an app relaunch. First, so an auto-play start already
                // knows the viewer's default player.
                externalPlayers = ExternalPlayerPlatform.shared.availablePlayers()
                if !autoPlayEvaluated {
                    autoPlayEvaluated = true
                    // `autoPlayArmed` was decided in `init` (BUG-183).
                    if autoPlayArmed {
                        autoPlay.arm()
                    } else if let notice {
                        showToast(notice)
                    }
                }
                rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
                model.start(forceManual: !autoPlayArmed)
                fetchEpisodesIfNeeded()
                // Head start for the player: addon subtitles for this title begin fetching while
                // the user is still choosing a stream, so the native path's pre-master window
                // (and the mpv side-load) see results instead of racing the network. The player's
                // own fetch call deduplicates against this one.
                SubtitleRepository.shared.fetchAddonSubtitles(type: type, videoId: videoId)
            }
            .onDisappear {
                pickerOnScreen = false
                invalidateYouTubeResolve()
                model.stop()
            }
            // Review r2 P3-2: every playback start (a row, "Try Next Source", auto-play, the Up
            // Next hand-off — every `selected = …` site) supersedes a YouTube resolve in flight.
            .onChange(of: selected?.id) { _, playing in
                if playing != nil {
                    coverIsCloseHold = false
                    invalidateYouTubeResolve()
                } else {
                    // BUG-174: the player is closing. Cover the list before its slide-down reveals
                    // it when the picker closes too; drop the cover when the list has to show.
                    prepareForPlayerClose()
                }
            }
            .fullScreenCover(item: playerCoverBinding, onDismiss: handlePlayerDismissed) { ctx in
                // `.id(ctx.id)` forces a full player rebuild when autoplay swaps in the next
                // episode's context (a same-position cover would otherwise keep the old libmpv
                // controller and just ignore the new context). Failover swaps in place the same
                // way (`PlaybackContext.attempt` keeps two candidates' ids apart).
                PlayerScreen(
                    context: ctx,
                    onPlayNext: { next in selected = next },
                    onPlaybackFailed: { failure in handlePlaybackFailure(failure, context: ctx) },
                    onPlaybackHealthy: { seconds in handlePlaybackHealthy(seconds, context: ctx) },
                    onOpenTitle: onOpenTitle
                )
                .ignoresSafeArea()
                .id(ctx.id)
            }
        }
        // Up Next failover: a picker for the episode whose source failed. Attached to the stack,
        // not beside the player cover, so the two presentations never share a view.
        .fullScreenCover(item: $failoverTarget, onDismiss: handleFailoverPickerDismissed) { target in
            StreamPickerView(
                type: target.context.contentType,
                videoId: target.context.videoId,
                title: target.context.title,
                parentMetaId: target.context.parentMetaId,
                season: target.context.season,
                episode: target.context.episode,
                episodes: target.context.episodes,
                poster: target.context.poster,
                episodeStill: target.context.episodeStill,
                synopsis: target.context.synopsis,
                meta: target.context.meta,
                logoUrl: logoUrl,
                forceManual: target.forceManual,
                startFromBeginning: false,
                notice: String(localized: "The next episode\u{2019}s source failed. Choose one below.")
            )
        }
    }

    /// "Start Over" still applies to the next playback this picker starts.
    private var startsOver: Bool { startFromBeginning && !startOverHonoured }

    /// The loading cover is up (BUG-183): auto mode is armed or working (not while a failover
    /// resolves behind the open player), or `coverHold` keeps it.
    private var loadingCoverVisible: Bool {
        StreamPickerCoverPolicy.showsCover(armed: autoPlayArmed, phase: autoPlay.phase,
                                           isFailoverWalk: autoPlay.isFailoverWalk, held: coverHold)
    }

    /// BUG-182/183: the cover itself, out of `body` so the type checker stays fast.
    private var loadingCover: some View {
        let cancel: (() -> Void)? = loadingCoverCancels ? { cancelAutoPlay() } : nil
        let line: String? = PlayerLoadingOverlay.episodeLine(
            season: season, episode: episode,
            episodes: episodes.isEmpty ? fetchedEpisodes : episodes)
        return FirstPlayAutoPlayOverlay(
            title: title,
            parentMetaId: parentMetaId,
            logoUrl: logoUrl,
            episodeLine: line,
            pulseKey: videoId,
            message: loadingCoverMessage,
            onCancel: cancel,
            showsLogo: !coverIsCloseHold
        )
    }

    /// BUG-185 (Steven rc9, D6): the player cover's binding. When the viewer closes the player and
    /// the picker is going to close too (`.closePicker`), the nil is written with animations
    /// disabled, so the player cover leaves without its slide-down and `handlePlayerDismissed`
    /// closes the picker straight after: Back lands on the opener in one pass. Every other close
    /// (the alert, the failover picker, the list) keeps the animated dismiss.
    private var playerCoverBinding: Binding<PlaybackContext?> {
        Binding(
            get: { selected },
            set: { newValue in
                guard newValue == nil, selected != nil, afterPlayerOutcome == .closePicker else {
                    selected = newValue
                    return
                }
                playerCloseRequestedAt = CFAbsoluteTimeGetCurrent()
                if StreamPickerCloseAnimation.uiKitFallback {
                    StreamPickerCloseAnimation.suspendUIKitAnimations()
                }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { selected = nil }
            }
        )
    }

    /// The cover's spoken label while auto mode works; nil while it is only held.
    private var loadingCoverMessage: String? {
        StreamPickerCoverPolicy.message(armed: autoPlayArmed, phase: autoPlay.phase,
                                        isFailoverWalk: autoPlay.isFailoverWalk)
    }

    /// Menu on the cover cancels auto mode only while auto mode is working; a held cover swallows it.
    private var loadingCoverCancels: Bool { loadingCoverMessage != nil }

    // MARK: - Group headers

    private static func headerKey(groupId: String) -> String { "header:\(groupId)" }

    /// Collapsed by default: a focusable header row per addon (name, stream count, chevron, and
    /// a per-addon spinner while that addon is still loading — the shared `AddonStreamGroup`
    /// carries `isLoading` per addon already, so this reflects real per-addon state rather than
    /// the global "any addon still loading" flag). Deliberately a plain `Button`, not
    /// `DisclosureGroup` — tvOS focus/highlight on `DisclosureGroup` is poor and inconsistent
    /// with the rest of this screen's rows.
    private func groupHeader(_ group: StreamsViewModel.Group) -> some View {
        let key = Self.headerKey(groupId: group.id)
        let isExpanded = expandedGroups.contains(group.id)

        return Button {
            toggleExpansion(group)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(Theme.Font.body)
                    .rowTextColor(secondary: true)
                    .frame(width: 20, alignment: .center)
                Text(group.addonName)
                    .font(Theme.Font.sectionTitle)
                    .rowTextColor()
                Text(group.streams.count == 1 ? String(localized: "1 stream") : String(localized: "\(group.streams.count) streams"))
                    .font(Theme.Font.caption)
                    .rowTextColor(secondary: true)
                if group.isLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xs + 2)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.settingsRow)
        .focused($focusedRow, equals: key)
    }

    private func toggleExpansion(_ group: StreamsViewModel.Group) {
        if expandedGroups.contains(group.id) {
            // Collapsing a group that currently holds focus would otherwise leave focus on a
            // row that's about to disappear from the hierarchy — retarget to the header first.
            if let focusedRow, focusedRow.hasPrefix("\(group.id)#") {
                self.focusedRow = Self.headerKey(groupId: group.id)
            }
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
            // Expanding keeps focus on the header (SwiftUI doesn't move it on select), matching
            // the requirement that expand never steals focus.
        }
    }

    // MARK: - Rows

    private func streamRow(_ stream: StreamItem, key: String) -> some View {
        // Kotlin nullable Strings surface as non-optional Swift String, so widen explicitly.
        let desc: String? = stream.description_
        let badges: [StreamBadge] = stream.badges
        let sizeBytes: Int64? = stream.behaviorHints.videoSize?.int64Value
        let showSize = model.showFileSizeBadges && sizeBytes != nil
        let hasBadgeRow = !badges.isEmpty || showSize

        return Button {
            manualFailoverList = model.groups.flatMap(\.streams)
            play(stream, rowKey: key)
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if hasBadgeRow && model.badgesOnTop {
                        badgeRow(badges: badges, sizeBytes: showSize ? sizeBytes : nil)
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(rowTitle(stream))
                            .font(Theme.Font.body)
                            .rowTextColor()
                            .lineLimit(2)
                        if resolvingKey == key {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    if let desc, !desc.isEmpty {
                        // BUG-16 (final form): 3 lines while browsing, unlimited on the FOCUSED
                        // row. Release names are dot/underscore-separated with no break points,
                        // so no fixed cap fits all of them ("works for some links but not all"
                        // — the reporter, on the 3-line beta.7 fix); expanding the row under
                        // focus guarantees the name you're actually reading is never truncated,
                        // without a marquee and without inflating every row in the list.
                        Text(desc)
                            .font(Theme.Font.caption)
                            .rowTextColor(secondary: true)
                            .lineLimit(focusedRow == key ? nil : 3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if hasBadgeRow && !model.badgesOnTop {
                        badgeRow(badges: badges, sizeBytes: showSize ? sizeBytes : nil)
                    }
                    // Batch D U2: the add-on gave only a YouTube video id — the row plays after an
                    // on-device resolve (the spinner above), so say where the video comes from.
                    if Self.isYouTubeResolved(stream) {
                        Text(verbatim: "YouTube")
                            .font(Theme.Font.caption)
                            .rowTextColor(secondary: true)
                    }
                    // Orivio batch item 2: this link failed recently for this title, so the
                    // automatic pickers skip it. Still selectable by hand.
                    if !rejectedKeys.isEmpty, rejectedKeys.contains(stream.playbackStreamKey) {
                        Text("Failed recently")
                            .font(Theme.Font.caption)
                            .rowTextColor(secondary: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.showAddonLogo {
                    addonLogoColumn(stream)
                }
            }
            .padding(.vertical, Theme.Spacing.xs + 2)
            .padding(.horizontal, Theme.Spacing.sm)
        }
        // `.settingsRow` (platter-free, soft white highlight + accent ring) replaces the system
        // `.glass` style: Liquid Glass's focus platter goes near-white, which made this row's
        // title text (statically `textPrimary`, near-white) unreadable on focus.
        .buttonStyle(.settingsRow)
        .focused($focusedRow, equals: key)
        // FEAT-5: long-press → the OTHER player(s). With the built-in default, the menu offers
        // the installed external players; with an external default (plain Select already hands
        // off) it inverts to offer "Play in NuvioTV Player" plus any non-default externals. The
        // modifier is skipped entirely when no external player is installed, so the long-press
        // stays inert rather than opening an empty menu.
        .modifier(ExternalPlayMenu(
            players: externalPlayers,
            defaultPlayerId: activeDefaultExternalPlayer?.id,
            onExternal: { player in
                externalPlay(stream, rowKey: key, playerId: player.id)
            },
            onBuiltIn: {
                manualFailoverList = model.groups.flatMap(\.streams)
                internalPlay(stream, rowKey: key)
            }
        ))
    }

    @ViewBuilder
    private func badgeRow(badges: [StreamBadge], sizeBytes: Int64?) -> some View {
        // BUG-16: this used to be one plain HStack with up to 8 badge chips (each up to
        // `StreamBadgeMetrics.maxImageWidth` = 180pt for image-based community badge packs) plus
        // the size chip — none of them width-flexible. An HStack whose children are all
        // non-shrinking ignores the width it's offered and reports the full sum of its children
        // back to its parent instead. That inflated "ideal" width bubbled up through the
        // title/description VStack and the row's outer HStack, widening the *whole row* — and
        // since every row shares one LazyVStack, effectively the whole list — past the screen.
        // The addon-logo column and the tail end of the badges/size chip then rendered off the
        // trailing edge, which is what testers saw as "no space left" for title/size/seeders.
        //
        // Fix: hand `ViewThatFits` a ladder of candidates from "every badge" down to "just an
        // overflow count", widest first. It measures each against the width actually left over
        // once title/description and the addon-logo column have claimed theirs, and renders the
        // first one that fits — so this row can never again demand more width than it's given.
        // The size chip is pinned first in every candidate since it's core metadata (like
        // seeders), not decoration, and every candidate shares the same fixed container height,
        // so switching between them never changes the row's height class.
        let displayBadges = Array(badges.prefix(8))
        let hiddenBeyondCap = max(0, badges.count - 8)
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: displayBadges.count, through: 0, by: -1)), id: \.self) { visible in
                badgeRowVariant(
                    displayBadges: displayBadges,
                    visibleCount: visible,
                    hiddenCount: (displayBadges.count - visible) + hiddenBeyondCap,
                    sizeBytes: sizeBytes
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One `ViewThatFits` candidate for `badgeRow`: the size chip (if any) + the first
    /// `visibleCount` badges + a non-focusable "+N" overflow chip for everything else.
    /// `hiddenCount` folds in both badges dropped by this candidate and any beyond the 8-badge
    /// display cap, so the count the user sees is always accurate.
    private func badgeRowVariant(
        displayBadges: [StreamBadge],
        visibleCount: Int,
        hiddenCount: Int,
        sizeBytes: Int64?
    ) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let sizeBytes {
                StreamFileSizeChip(bytes: sizeBytes)
            }
            ForEach(Array(displayBadges.prefix(visibleCount).enumerated()), id: \.offset) { _, badge in
                StreamBadgeChipView(badge: badge)
            }
            if hiddenCount > 0 {
                BadgeOverflowChip(count: hiddenCount)
            }
        }
    }

    private func addonLogoColumn(_ stream: StreamItem) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            let logo: String? = stream.addonLogo
            if let logo, !logo.isEmpty, let url = URL(string: logo) {
                // Cached + downsampled: the same logo repeats on every row of a group, and the
                // uncached `AsyncImage` refetched and re-decoded it as each row was realized.
                // Clear while loading and on failure, like the old AsyncImage: add-on logos often
                // 404, and a shimmer or grey film tile on every row of the group is noise.
                CachedAsyncImage(url: url, contentMode: .fit, decodeSize: .points(width: 44, height: 44),
                                 loading: { Color.clear }, failure: { Color.clear })
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(stream.addonName)
                .font(Theme.Font.caption)
                .rowTextColor(secondary: true)
                .lineLimit(1)
        }
        .frame(width: 150)
    }

    /// Row title with the mobile "- <Provider> Instant" suffix on debrid-cached torrent rows
    /// (`StreamCard.kt:instantServiceLabel`), shown only while debrid resolution is enabled and
    /// no custom stream-name template is active.
    private func rowTitle(_ stream: StreamItem) -> String {
        let base = stream.streamLabel
        guard model.instantSuffixEnabled,
              let status = stream.debridCacheStatus,
              status.state == .cached else { return base }
        var provider = DebridProviders.shared.shortName(id: status.providerId)
        if provider.trimmingCharacters(in: .whitespaces).isEmpty {
            provider = status.providerName.trimmingCharacters(in: .whitespaces)
        }
        if provider.isEmpty {
            provider = DebridProviders.shared.displayName(id: status.providerId)
        }
        return provider.isEmpty ? base : String(localized: "\(base) - \(provider) Instant")
    }

    // MARK: - Playback / debrid resolve

    /// The validated default external player, or nil for built-in. Membership in the probed
    /// `externalPlayers` list is required — a stale stored id (player uninstalled since it was
    /// chosen) must not hijack every Select into a failed handoff.
    private var activeDefaultExternalPlayer: ExternalPlayerApp? {
        guard !defaultExternalPlayerId.isEmpty else { return nil }
        return externalPlayers.first { $0.id == defaultExternalPlayerId }
    }

    /// Select on a stream row. Routes to the user's default player (Settings → Player):
    /// external default ⇒ hand off (with automatic fallback to the built-in player if the
    /// handoff fails), otherwise the built-in pipeline.
    private func play(_ stream: StreamItem, rowKey: String) {
        if let defaultPlayer = activeDefaultExternalPlayer {
            externalPlay(stream, rowKey: rowKey, playerId: defaultPlayer.id, fallbackToInternal: true)
            return
        }
        internalPlay(stream, rowKey: rowKey)
    }

    /// A built-in-player playback the viewer chose (a row, the long-press menu, "Try Next Source",
    /// whose `attempt` counts the failed tries before it). Always `.manual`.
    private func internalPlay(_ stream: StreamItem, rowKey: String, attempt: Int = 0) {
        let streamKey = stream.playbackStreamKey
        let direct: String? = stream.playableDirectUrl
        if let direct, !direct.isEmpty, let url = URL(string: direct) {
            // A manual stream pick is user interaction — reset the Still Watching run.
            NextEpisodeEngine.consecutiveAutoPlays = 0
            selected = context(url: url, stream: stream, listedStream: stream, streamKey: streamKey,
                               launchSource: .manual, attempt: attempt)
            return
        }

        // Batch D U2 (upstream 94976222): the add-on gave only a YouTube video id — resolve it on
        // the device to one playable URL (HLS master, else progressive), then play that exactly
        // like a direct link. The listed stream stays the identity (`streamKey`, `listedStream`):
        // the resolved link expires within hours.
        if Self.isYouTubeResolved(stream) {
            guard resolvingKey == nil else { return }
            let token = beginYouTubeResolve(rowKey: rowKey)
            youTubeResolveTask = resolveYouTube(stream) { resolved in
                // Review r1 / r2 P3-2: only the request the token belongs to may act; a playback
                // the viewer started since (another row, "Try Next Source", an auto-play pick,
                // even one already dismissed again) dropped the token, and so did leaving the
                // picker (a Menu press during the resolve).
                guard youTubeResolveToken == token else {
                    print("[StreamPicker] YouTube resolve landed after another playback started — dropped")
                    return
                }
                finishYouTubeResolve()
                guard selected == nil, pickerOnScreen else { return }
                let resolvedUrl: String? = resolved?.playableDirectUrl
                guard let resolved, let resolvedUrl, !resolvedUrl.isEmpty, let url = URL(string: resolvedUrl) else {
                    showToast(Self.youTubeResolveFailedMessage)
                    return
                }
                NextEpisodeEngine.consecutiveAutoPlays = 0
                selected = context(url: url, stream: resolved, listedStream: stream, streamKey: streamKey,
                                   launchSource: .manual, attempt: attempt)
            }
            return
        }

        // Torrent / clientResolve result → resolve through the in-app debrid connection.
        guard resolvingKey == nil else { return }
        guard DirectDebridPlaybackResolver.shared.shouldResolveToPlayableStream(stream: stream) else {
            showToast(String(localized: "This stream needs a debrid account. Connect one in Settings \u{2192} Services \u{2192} Debrid."))
            return
        }
        resolvingKey = rowKey
        let kotlinSeason = season.map { KotlinInt(int: Int32($0)) }
        let kotlinEpisode = episode.map { KotlinInt(int: Int32($0)) }
        // The `@Throws` twin: a Kotlin exception out of the plain suspend export aborts the process.
        Task { @MainActor in
            let result: DirectDebridPlayableResult?
            do {
                result = try await DirectDebridPlaybackResolver.shared.resolveToPlayableStreamChecked(
                    stream: stream, season: kotlinSeason, episode: kotlinEpisode
                )
            } catch {
                print("[StreamPicker] debrid resolve threw: \(error)")
                result = nil
            }
            resolvingKey = nil
            if let success = result as? DirectDebridPlayableResult.Success {
                let resolvedUrl: String? = success.stream.playableDirectUrl
                if let resolvedUrl, !resolvedUrl.isEmpty, let url = URL(string: resolvedUrl) {
                    NextEpisodeEngine.consecutiveAutoPlays = 0
                    selected = context(url: url, stream: success.stream, listedStream: stream, streamKey: streamKey,
                                       launchSource: .manual, attempt: attempt)
                    return
                }
            }
            showToast(Self.resolveFailureMessage(result))
            // The toast promises a refresh — deliver it: stale cached links mean the whole
            // result set is old, so re-fetch (focus is preserved; see onChange guard).
            if result is DirectDebridPlayableResult.Stale {
                model.reload(forceManual: !autoPlayArmed)
            }
        }
    }

    // MARK: - YouTube resolve (batch D U2)

    /// True when the add-on gave this stream only a YouTube video id (shared `youTubeIdToResolve`).
    /// nil → false, so callers can pass an optional listed stream. Pure and `nonisolated`: the
    /// Up Next engine's stream predicates and `PlaybackFailoverPolicy` call it off the main actor.
    nonisolated static func isYouTubeResolved(_ stream: StreamItem?) -> Bool {
        let youTubeId: String? = stream?.youTubeIdToResolve
        return !(youTubeId ?? "").isEmpty
    }

    static var youTubeResolveFailedMessage: String { String(localized: "Could not load this YouTube video.") }

    /// Resolves a ytId-only stream to a copy carrying one playable URL through the shared
    /// `YouTubeStreamResolver` (the trailer extractor; HLS master playlist, else progressive). The
    /// shared function maps every failure to nil and rethrows only cancellation (review r1 F3),
    /// which `try?` also turns into nil — so a nil is "could not resolve" unless this Task itself
    /// was cancelled, in which case nobody is told anything. Runs on the main actor throughout
    /// (the async export, not the completion-handler twin, so no `@Sendable` hop is needed).
    @discardableResult
    private func resolveYouTube(_ stream: StreamItem, completion: @escaping @MainActor (StreamItem?) -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            let resolved: StreamItem? = try? await YouTubeStreamResolver.shared.resolve(stream: stream)
            guard !Task.isCancelled else { return }
            completion(resolved)
        }
    }

    /// Starts a YouTube resolve for `rowKey`: the row spinner (`resolvingKey`, which also keeps
    /// resolves one at a time) plus a fresh request token (review r2 P3-2). Returns the token the
    /// completion must still hold to act.
    private func beginYouTubeResolve(rowKey: String) -> UUID {
        let token = UUID()
        resolvingKey = rowKey
        youTubeResolveToken = token
        return token
    }

    /// The owning completion is done (either way): clears the spinner and the token.
    private func finishYouTubeResolve() {
        resolvingKey = nil
        youTubeResolveToken = nil
        youTubeResolveTask = nil
    }

    /// Supersedes the YouTube resolve in flight, if any: its completion will find a stale token,
    /// its Task is cancelled (review r2 P3-3), and the spinner it owned is cleared so the
    /// one-at-a-time guard reopens. A debrid resolve's spinner (no token) is left alone.
    private func invalidateYouTubeResolve() {
        guard youTubeResolveToken != nil else { return }
        youTubeResolveToken = nil
        youTubeResolveTask?.cancel()
        youTubeResolveTask = nil
        resolvingKey = nil
    }

    // MARK: - External player handoff (FEAT-5)

    /// Hands the stream to an installed external player (Infuse today) instead of the in-app
    /// player — reached from a row long-press, or from plain Select when that player is the
    /// user's default. Mirrors `internalPlay(_:rowKey:)`'s two branches — direct URLs open
    /// immediately; torrent/clientResolve results go through the same debrid resolve first,
    /// reusing `resolvingKey` so the row spinner and the one-at-a-time guard behave identically
    /// for both destinations.
    ///
    /// `fallbackToInternal` is set on the default-player route only: a failed handoff there
    /// would strand a user whose Select no longer plays anything, so it degrades to the built-in
    /// player. The explicit long-press route keeps the honest failure toast instead — the user
    /// asked for Infuse specifically, silently playing elsewhere would be surprising.
    private func externalPlay(_ stream: StreamItem, rowKey: String, playerId: String, fallbackToInternal: Bool = false) {
        let direct: String? = stream.playableDirectUrl
        if let direct, !direct.isEmpty {
            openExternally(urlString: direct, stream: stream, listed: stream, playerId: playerId,
                           rowKey: rowKey, fallbackToInternal: fallbackToInternal)
            return
        }

        // Batch D U2: a ytId-only stream resolves on the device first (see `internalPlay`), then
        // the resolved link is handed off like a direct one.
        if Self.isYouTubeResolved(stream) {
            guard resolvingKey == nil else { return }
            let token = beginYouTubeResolve(rowKey: rowKey)
            youTubeResolveTask = resolveYouTube(stream) { resolved in
                // Review r1 / r2 P3-2: same token guard as `internalPlay` — a Menu press during
                // the resolve must not launch an external player from a view that is gone.
                guard youTubeResolveToken == token else {
                    print("[StreamPicker] YouTube resolve landed after the picker moved on — dropped")
                    return
                }
                finishYouTubeResolve()
                guard selected == nil, pickerOnScreen else { return }
                let resolvedUrl: String? = resolved?.playableDirectUrl
                guard let resolved, let resolvedUrl, !resolvedUrl.isEmpty else {
                    showToast(Self.youTubeResolveFailedMessage)
                    return
                }
                openExternally(urlString: resolvedUrl, stream: resolved, listed: stream, playerId: playerId,
                               rowKey: rowKey, fallbackToInternal: fallbackToInternal)
            }
            return
        }

        guard resolvingKey == nil else { return }
        guard DirectDebridPlaybackResolver.shared.shouldResolveToPlayableStream(stream: stream) else {
            showToast(String(localized: "This stream needs a debrid account. Connect one in Settings \u{2192} Services \u{2192} Debrid."))
            return
        }
        resolvingKey = rowKey
        let kotlinSeason = season.map { KotlinInt(int: Int32($0)) }
        let kotlinEpisode = episode.map { KotlinInt(int: Int32($0)) }
        // The `@Throws` twin: a Kotlin exception out of the plain suspend export aborts the process.
        Task { @MainActor in
            let result: DirectDebridPlayableResult?
            do {
                result = try await DirectDebridPlaybackResolver.shared.resolveToPlayableStreamChecked(
                    stream: stream, season: kotlinSeason, episode: kotlinEpisode
                )
            } catch {
                print("[StreamPicker] debrid resolve threw: \(error)")
                result = nil
            }
            resolvingKey = nil
            if let success = result as? DirectDebridPlayableResult.Success {
                let resolvedUrl: String? = success.stream.playableDirectUrl
                if let resolvedUrl, !resolvedUrl.isEmpty {
                    openExternally(
                        urlString: resolvedUrl,
                        stream: success.stream,
                        listed: stream,
                        playerId: playerId,
                        rowKey: rowKey,
                        fallbackToInternal: fallbackToInternal
                    )
                    return
                }
            }
            showToast(Self.resolveFailureMessage(result))
            if result is DirectDebridPlayableResult.Stale {
                model.reload(forceManual: !autoPlayArmed)
            }
        }
    }

    /// Builds the shared playback request and opens the target player via its x-callback-url
    /// scheme. Title/season/episode feed `buildPlayerTitle()` so Infuse shows
    /// "Show — S02E05" instead of a bare debrid CDN filename. Must run on the main thread
    /// (UIApplication.open under the hood).
    ///
    /// FEAT-21 (beta.12): the handoff now carries what the internal player would use —
    /// `resumePositionMs` from the same `progressForVideo` lookup MPV's resume path runs (same
    /// >10s floor, completed entries excluded), and the stream's addon subtitles, so players
    /// whose URL builders consume `sub`/`position` (VidHub `/play`, Infuse, VLC) resume and
    /// subtitle like the built-in player instead of starting cold.
    ///
    /// Orivio batch item 5: a handoff to a player that reports back (`returnReportingPlayerIds`:
    /// Infuse, SenPlayer since FEAT-56, Native Player since FEAT-78) first prepares a shared external-playback session and
    /// passes the player its x-success / x-error callback URLs on this install's own URL scheme, so
    /// the position it reports back is recorded (`ExternalPlaybackReturn`). A handoff that does not
    /// open drops that session again. `listed` is the stream as the list shows it (pre-resolve).
    ///
    /// `autoAttempt` (1-based) marks the first-play auto start handing its pick to the viewer's
    /// external default: its built-in fallback is then an auto start too (`.autoPlay`, the walk
    /// continues on a failure).
    ///
    /// D5 (Steven rc7): the request also carries the add-on subtitles this picker fetched
    /// (`SubtitleRepository`, prefetched since the picker opened), the stream's own first, then the
    /// viewer's preferred subtitle language first (`ExternalSubtitleHandOff`). When that fetch has
    /// not finished, the hand-off waits for it at most `ExternalSubtitleHandOff.waitSeconds`
    /// (row spinner on, one hand-off at a time) and then sends what has arrived.
    ///
    /// BUG-174 (Steven rc7): a hand-off that opened closes the picker, manual picks included (the
    /// auto path always did), so coming back from the external player lands on the page the viewer
    /// started from.
    private func openExternally(urlString: String, stream: StreamItem, listed: StreamItem, playerId: String,
                                rowKey: String? = nil, fallbackToInternal: Bool = false, autoAttempt: Int? = nil) {
        // Review r1 (P2): one hand-off at a time. The subtitle wait makes this asynchronous, so a
        // second Select during it would otherwise open the external player twice.
        guard !externalHandOffInFlight else { return }
        externalHandOffInFlight = true
        let spinnerKey = rowKey ?? Self.handOffRowKey
        resolvingKey = spinnerKey
        let type = type
        let videoId = videoId
        Task { @MainActor in
            let addonSubtitles = await ExternalSubtitleHandOff.liveAddonSubtitles(type: type, videoId: videoId)
            externalHandOffInFlight = false
            if resolvingKey == spinnerKey { resolvingKey = nil }
            // The viewer left the picker, or something else started playing, while it waited.
            guard pickerOnScreen, selected == nil else {
                print("[StreamPicker] external hand-off dropped: the picker moved on while subtitles loaded")
                return
            }
            openExternallyNow(urlString: urlString, stream: stream, listed: listed, playerId: playerId,
                              addonSubtitles: addonSubtitles, fallbackToInternal: fallbackToInternal,
                              autoAttempt: autoAttempt)
        }
    }

    /// `openExternally` once the add-on subtitles are in hand.
    private func openExternallyNow(urlString: String, stream: StreamItem, listed: StreamItem, playerId: String,
                                   addonSubtitles: [AddonSubtitle], fallbackToInternal: Bool, autoAttempt: Int?) {
        let progress = WatchProgressRepository.shared.progressForVideo(
            videoId: videoId,
            parentMetaId: parentMetaId,
            seasonNumber: season.map { KotlinInt(int: Int32($0)) },
            episodeNumber: episode.map { KotlinInt(int: Int32($0)) }
        )
        // Percentage-only rows (Simkl/Trakt) stay 0 here: the real duration is unknown before the
        // file opens, and scaling by the show runtime is the bug being avoided. "Start Over" sends 0.
        let resumeMs: Int64 = {
            guard !startsOver else { return 0 }
            guard let progress, !progress.isCompleted, progress.lastPositionMs > 10_000 else { return 0 }
            return progress.lastPositionMs
        }()
        var launchSessionId: String?
        var callbackSuccessUrl: String?
        var callbackErrorUrl: String?
        if Self.returnReportingPlayerIds.contains(playerId), let sourceURL = URL(string: urlString) {
            let session = ExternalPlaybackReturn.shared.prepare(
                playerId: playerId,
                sourceUrl: urlString,
                // `listedStream: listed` so a ytId-only stream's session stores no expiring link.
                playbackSession: PlaybackProgressRecorder.playbackSession(
                    for: context(url: sourceURL, stream: stream, listedStream: listed)),
                durationMs: externalDurationMs(progress: progress).map { KotlinLong(value: $0) }
            )
            let callbacks = ExternalPlaybackCallbacks.shared.build(
                scheme: AppCallbackScheme.value, playerId: playerId, sessionId: session.id
            )
            launchSessionId = session.id
            callbackSuccessUrl = callbacks.first.map { $0 as String }
            callbackErrorUrl = callbacks.second.map { $0 as String }
        }
        let subtitles = ExternalSubtitleHandOff.requestSubtitles(stream: stream, addonSubtitles: addonSubtitles)
        print("[StreamPicker] external hand-off player=\(playerId) subtitles=\(subtitles.count) (stream=\(stream.externalSubtitles.count) addon=\(addonSubtitles.count))")
        let request = ExternalPlayerPlaybackRequest(
            sourceUrl: urlString,
            title: title,
            streamTitle: nil,
            sourceHeaders: [:],
            resumePositionMs: resumeMs,
            // Each player's builder keeps its own rules (VLC/VidHub take the first; Native
            // Player keeps http(s) SRT only), so the order here is what decides.
            subtitles: subtitles,
            season: season.map { KotlinInt(int: Int32($0)) },
            episode: episode.map { KotlinInt(int: Int32($0)) },
            episodeTitle: nil,
            skipSegmentsJson: nil,
            // Infuse and SenPlayer only (nil for every other player): where the player reports the
            // stop position.
            callbackSuccessUrl: callbackSuccessUrl,
            callbackErrorUrl: callbackErrorUrl
        )
        // BUG-185 (Steven rc9, D6): build the URL, close the picker FIRST, then leave the app, so
        // coming back from the external player lands on the opener with no loading cover to flash
        // (the old order opened the player while the picker, under its cover, was still up).
        let intent = ExternalPlayerPlatform.shared.buildIntent(request: request, playerId: playerId)
        if let success = intent as? ExternalPlayerIntentResultSuccess, let url = success.intent as? URL {
            if UserDefaults.standard.bool(forKey: "debug.extPlayerProbe") {
                // Knob-gated, console-only (the shared `open` rule): the URL embeds debrid tokens.
                NSLog("%@", "[ExtPlayerProbe] open player=\(playerId) url=\(url.absoluteString)")
            }
            // BUG-174: handed off — the picker leaves (manual picks too); Back from the external
            // player returns to the page that opened it.
            closePicker()
            let sessionId = launchSessionId
            // Not capturing the view: the picker is dismissing by the time this runs.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                UIApplication.shared.open(url, options: [:]) { opened in
                    // Upstream 99ced26a (as `ExternalPlayerPlatform.apple.kt`'s `open`): a launch
                    // that carried a return callback but never opened drops its pending session
                    // (`cancelLaunch(sessionId:)` only drops it if it is still this one).
                    if !opened, let sessionId {
                        print("[StreamPicker] external player did not open; dropping its return session")
                        ExternalPlaybackReturn.shared.cancelLaunch(sessionId: sessionId)
                    }
                }
            }
            return
        }
        if let launchSessionId {
            // Nothing was handed off: drop the pending return session (only if it is still this one).
            ExternalPlaybackReturn.shared.cancelLaunch(sessionId: launchSessionId)
        }
        if fallbackToInternal, let url = URL(string: urlString) {
            showToast(String(localized: "Couldn\u{2019}t open the external player \u{2014} playing in NuvioTV."))
            NextEpisodeEngine.consecutiveAutoPlays = 0
            if let autoAttempt {
                autoPlayLog("[AutoPlay] external player \(playerId) did not open — attempt #\(autoAttempt) plays in NuvioTV")
                selected = context(url: url, stream: stream, listedStream: listed, streamKey: listed.playbackStreamKey,
                                   launchSource: .autoPlay, attempt: autoAttempt - 1)
            } else {
                selected = context(url: url, stream: stream, listedStream: listed, streamKey: listed.playbackStreamKey,
                                   launchSource: .manual)
            }
        } else {
            // An auto pick's cover was held for the hand-off: the list shows with the toast.
            coverHold = false
            showToast(String(localized: "Couldn\u{2019}t open the external player."))
        }
    }

    /// Duration for the external-player return: the stored progress entry's, else the episode's
    /// runtime, else the title's catalog runtime. nil = unknown (the shared side then records the
    /// position without a tracker scrobble).
    private func externalDurationMs(progress: WatchProgressEntry?) -> Int64? {
        if let progress, progress.durationMs > 0 { return progress.durationMs }
        let all = episodes.isEmpty ? fetchedEpisodes : episodes
        if let season, let episode,
           let video = all.first(where: { $0.season?.intValue == season && $0.episode?.intValue == episode }),
           let minutes = video.runtime?.intValue, minutes > 0 {
            return Int64(minutes) * 60_000
        }
        if let minutes = PlaybackMeta.runtimeMinutes(meta?.runtime), minutes > 0 {
            return Int64(minutes) * 60_000
        }
        return nil
    }

    // MARK: - First-play auto mode (orivio batch item 1)

    /// "Auto-Play Best Source" is the shared FIRST_STREAM auto-play mode.
    private static func firstStreamAutoPlayOn() -> Bool {
        PlayerSettingsRepository.shared.ensureLoaded()
        let settings = PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState
        return settings?.streamAutoPlayMode == StreamAutoPlayMode.firstStream
    }

    private func handleAutoPlayEvent(_ event: FirstPlayAutoPlayController.Event) {
        switch event {
        case let .play(candidate, resolved, url, attempt, isFailover):
            if isFailover, selected == nil {
                // The viewer closed the failed player while the next candidate resolved.
                autoPlayLog("[AutoPlay] failover result after the player closed — dropped")
                return
            }
            // BUG-183: the cover stays up while the player is presented (`.done` alone would hide
            // it and show the list for a beat before the player's cover is up).
            coverHold = true
            autoPlayArmed = false
            NextEpisodeEngine.consecutiveAutoPlays = 0
            if case let .external(playerId) = FirstPlayAutoPlayController.Policy.startDestination(
                isFailover: isFailover, defaultExternalPlayerId: activeDefaultExternalPlayer?.id
            ) {
                // The viewer's default player is external: the auto pick goes there, as Select on a
                // row would. Handed off, the picker leaves too (`openExternally`, BUG-174); a
                // handoff that does not open plays in NuvioTV as this same auto start.
                autoPlayLog("[AutoPlay] attempt #\(attempt) to external player \(playerId) key=\(candidate.streamKey)")
                openExternally(urlString: url.absoluteString, stream: resolved, listed: candidate.stream,
                               playerId: playerId, fallbackToInternal: true, autoAttempt: attempt)
                return
            }
            // Set straight from the event: during a failover this swaps the open player in place.
            selected = context(url: url, stream: resolved, listedStream: candidate.stream,
                               streamKey: candidate.streamKey, launchSource: .autoPlay, attempt: attempt - 1)
        case let .gaveUp(reason, duringFailover):
            autoPlayArmed = false
            rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
            if duringFailover {
                // The viewer already left the player: nothing to explain. Review r1 (P3): the cover
                // stays, the picker is closing behind the player.
                guard selected != nil else {
                    autoPlayLog("[AutoPlay] walk ended (\(reason)) after the player had closed — nothing shown, rejected=\(rejectedKeys.count)")
                    return
                }
                // BUG-174: this close shows the list (with the toast below), not the opener.
                keepListAfterPlayer = true
                selected = nil
            }
            coverHold = false
            let listedStreams = model.groups.reduce(0) { $0 + $1.streams.count }
            autoPlayLog("[AutoPlay] walk ended (\(reason)) — showing the list: groups=\(model.groups.count) streams=\(listedStreams) rejected=\(rejectedKeys.count) failover=\(duringFailover)")
            if duringFailover || !model.groups.isEmpty {
                showToast(String(localized: "No source could start. Choose one below."))
            }
            focusListAfterAutoPlay()
        }
    }

    /// Menu on the overlay: stop auto mode and show the list; the picker stays.
    private func cancelAutoPlay() {
        autoPlay.cancel(why: "Menu on the overlay")
        autoPlayArmed = false
        coverHold = false
        focusListAfterAutoPlay()
    }

    /// Initial focus for the list once the overlay lifts (same targets as the first-groups rule).
    private func focusListAfterAutoPlay() {
        DispatchQueue.main.async {
            guard focusedRow == nil || focusedRow == Self.testRowKey else { return }
            let ids = model.groups.map(\.id)
            if ids.count == 1, expandedGroups.contains(ids[0]), let firstKey = model.firstRowKey {
                focusedRow = firstKey
            } else if let firstId = ids.first {
                focusedRow = Self.headerKey(groupId: firstId)
            }
        }
    }

    // MARK: - Failover (orivio batch item 2)

    /// A playback this picker presented failed. The link is remembered when it never got going,
    /// then the launch source decides: swap in the next auto candidate, open a picker for the Up
    /// Next episode, or close to the "Try Next Source" alert.
    private func handlePlaybackFailure(_ failure: PlaybackFailure, context ctx: PlaybackContext) {
        guard selected?.id == ctx.id else {
            print("[Failover] failure for a context no longer presented — ignored")
            return
        }
        print("[Failover] failure source=\(ctx.launchSource) attempt=\(ctx.attempt) played=\(Int(failure.secondsPlayed))s key=\(ctx.streamKey) kind=\(failure.kind.rawValue) http=\(failure.httpStatus.map(String.init) ?? "-") reason=\(failure.reason)")
        if PlaybackFailoverPolicy.shouldKeep(secondsPlayed: failure.secondsPlayed), ctx.videoId == videoId {
            startOverHonoured = true
        }
        if !failure.kind.remembersLink, failure.secondsPlayed < PlaybackFailoverPolicy.healthySeconds {
            // BUG-143: the link is fine (network / offline / cancelled / our own engine), and its
            // debrid resolve is still good: neither remembered nor invalidated.
            print("[Failover] reject key=\(ctx.streamKey) kind=\(failure.kind.rawValue) transient=1 skipped")
        }
        if PlaybackFailoverPolicy.shouldReject(failure) {
            RejectedStreamLinks.reject(ctx.streamKey, title: ctx.videoId)
            if let listed = ctx.listedStream, listed.isAddonDebridCandidate {
                // The resolver would hand the same dead link back for 15 minutes.
                DirectDebridPlaybackResolver.shared.invalidate(
                    stream: listed,
                    season: ctx.season.map { KotlinInt(int: Int32($0)) },
                    episode: ctx.episode.map { KotlinInt(int: Int32($0)) }
                )
            }
        }
        rejectedKeys = RejectedStreamLinks.rejected(for: videoId)

        var response = PlaybackFailoverPolicy.response(for: ctx.launchSource)
        if response == .manualAlert, ctx.videoId != videoId {
            // An in-player source switch on a later episode failed: this picker's list is the
            // wrong title, so open that episode's own picker on its list instead.
            response = .nextEpisodePicker
        }
        switch response {
        case .autoFailover:
            if !autoPlay.failover(afterFailureOf: ctx.streamKey, addonId: ctx.providerAddonId) {
                handleAutoPlayEvent(.gaveUp(.allFailed, duringFailover: true))
            }
        case .nextEpisodePicker:
            let forceManual = ctx.launchSource == .manual || !Self.firstStreamAutoPlayOn()
            pendingFailoverTarget = FailoverTarget(context: ctx, forceManual: forceManual)
            selected = nil
        case .manualAlert:
            var retryContext: PlaybackContext?
            var retryEngine: PlaybackEngine?
            if failure.otherEngineEligible {
                let engine: PlaybackEngine = failure.engine == .mpv ? .native : .mpv
                var retry = ctx
                retry.forcedEngine = engine
                retry.resumeAtSec = failure.positionSec
                retry.attempt = ctx.attempt + 1
                retry.launchSource = .manual
                retryContext = retry
                retryEngine = engine
            }
            pendingManualFailureAlert = ManualFailureAlert(
                reason: failure.reason,
                next: nextManualStream(after: ctx),
                attempt: ctx.attempt + 1,
                retry: retryContext,
                retryEngine: retryEngine
            )
            selected = nil
        }
    }

    /// The link played long enough to count as healthy: forget an earlier failure of it.
    private func handlePlaybackHealthy(_ seconds: Double, context ctx: PlaybackContext) {
        guard PlaybackFailoverPolicy.shouldKeep(secondsPlayed: seconds) else { return }
        RejectedStreamLinks.keep(ctx.streamKey, title: ctx.videoId)
        if ctx.videoId == videoId {
            startOverHonoured = true
            rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
        }
    }

    /// The stream "Try Next Source" plays after `ctx`'s: the list as it was when the viewer picked
    /// (falling back to the live list), after the failed one, same add-on first, failed links skipped.
    private func nextManualStream(after ctx: PlaybackContext) -> StreamItem? {
        let list = manualFailoverList.isEmpty ? model.groups.flatMap(\.streams) : manualFailoverList
        guard let index = PlaybackFailoverPolicy.nextManualIndex(
            streams: list,
            failedKey: ctx.streamKey,
            failedAddonId: ctx.providerAddonId,
            rejected: RejectedStreamLinks.rejected(for: videoId)
        ) else { return nil }
        return list[index]
    }

    /// What the closing player leads to (BUG-174): the queued alert, the queued Up Next failover
    /// picker, the list (an auto walk that ended with nothing), or — everything else, manual picks
    /// included — closing the picker so Back lands on the page that opened it.
    private var afterPlayerOutcome: StreamPickerExitPolicy.AfterPlayer {
        StreamPickerExitPolicy.afterPlayerClosed(
            alertQueued: pendingManualFailureAlert != nil,
            failoverPickerQueued: pendingFailoverTarget != nil,
            listRequested: keepListAfterPlayer
        )
    }

    /// `selected` went nil (the player is closing; its slide-down has not revealed the list yet).
    /// BUG-174: when the picker closes too (or the Up Next failover picker takes over), the loading
    /// cover goes over the list first, with no animation, so the list never shows on the way out;
    /// when the list has to show (the alert, an ended walk), the cover drops.
    private func prepareForPlayerClose() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            switch afterPlayerOutcome {
            case .closePicker:
                coverHold = true
                coverIsCloseHold = true
            case .openFailoverPicker:
                coverHold = true
                coverIsCloseHold = false
            case .raiseAlert, .keepList:
                coverHold = false
                coverIsCloseHold = false
            }
        }
    }

    /// The player cover closed. A context swap (failover, Up Next) re-presents instead and leaves
    /// `selected` set; a real close raises whatever the failure queued — never in the same runloop
    /// as the dismissal — or closes the picker as well (BUG-174, Steven rc7: Back from a player
    /// returns to the page you started from, manual picks included; D1).
    private func handlePlayerDismissed() {
        StreamPickerCloseAnimation.resumeUIKitAnimations()
        if let requestedAt = playerCloseRequestedAt {
            playerCloseRequestedAt = nil
            let ms = Int((CFAbsoluteTimeGetCurrent() - requestedAt) * 1000)
            print("[StreamPicker] BUG-185 player close: setter \u{2192} onDismiss \(ms) ms uiKitFallback=\(StreamPickerCloseAnimation.uiKitFallback ? 1 : 0)")
        }
        guard selected == nil else { return }
        rejectedKeys = RejectedStreamLinks.rejected(for: videoId)
        let outcome = afterPlayerOutcome
        // Review r1 (P3): read once per close, so it never carries to the next one.
        keepListAfterPlayer = false
        switch outcome {
        case .raiseAlert:
            guard let pending = pendingManualFailureAlert else { return }
            pendingManualFailureAlert = nil
            coverHold = false
            coverIsCloseHold = false
            DispatchQueue.main.async { manualFailureAlert = pending }
        case .openFailoverPicker:
            guard let pending = pendingFailoverTarget else { return }
            pendingFailoverTarget = nil
            // The nested picker's own close closes this one too: the cover keeps the list hidden
            // under it and on the way out.
            coverHold = true
            coverIsCloseHold = false
            DispatchQueue.main.async { failoverTarget = pending }
        case .keepList:
            keepListAfterPlayer = false
            coverHold = false
            coverIsCloseHold = false
            autoPlay.cancel(why: "player closed")
        case .closePicker:
            // A failover still resolving behind the closed player must not reopen it.
            autoPlay.cancel(why: "player closed")
            closePicker()
        }
    }

    /// The Up Next failover picker closed (Back from its list, or its own player closed it).
    /// BUG-174: this picker's list is for the episode before, so the picker closes as well and
    /// Back lands on the page that opened it.
    private func handleFailoverPickerDismissed() {
        closePicker()
    }

    /// BUG-174: closes the picker without the list showing — the cover goes up and both changes
    /// run without animation (the picker's own slide-down would otherwise reveal the list).
    private func closePicker() {
        var instant = Transaction()
        instant.disablesAnimations = true
        // BUG-185: the close-time hold is plain black (no logo flash on the way out).
        withTransaction(instant) {
            coverHold = true
            coverIsCloseHold = true
        }
        // Not gated on `pickerOnScreen`: the player's full-screen cover can take the picker off
        // screen (`onDisappear`) until after this runs.
        DispatchQueue.main.async {
            withTransaction(instant) { dismiss() }
        }
    }

    /// Mirrors the shared `DirectDebridPlayableResult.toastMessage()` wording (tvOS renders the
    /// English fallbacks; matching locally avoids depending on the ext-fun's bridged name).
    /// BUG-21: `Error` now carries a step-specific diagnostic ("TorBox: adding the item failed
    /// (HTTP 403 · BAD_TOKEN: …)") built shared-side — show it verbatim so a tester's toast
    /// names the exact failing call instead of the old catch-all.
    private static func resolveFailureMessage(_ result: DirectDebridPlayableResult?) -> String {
        switch result {
        case is DirectDebridPlayableResult.MissingApiKey:
            return String(localized: "Connect an account in Settings \u{2192} Services \u{2192} Debrid.")
        case is DirectDebridPlayableResult.NotCached:
            return String(localized: "Not cached on your debrid service.")
        case is DirectDebridPlayableResult.Stale:
            return String(localized: "This link expired. Refreshing results.")
        case let error as DirectDebridPlayableResult.Error:
            return error.message ?? String(localized: "Could not open this link.")
        default:
            return String(localized: "Could not open this link.")
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        let shown = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if toast == shown {
                withAnimation { toast = nil }
            }
        }
    }

    /// The Up Next episode (or other foreign video) whose playback failed, for the nested picker.
    private struct FailoverTarget: Identifiable {
        let id = UUID()
        let context: PlaybackContext
        /// Open on the list (auto-play off, or the failed link was the viewer's own pick).
        let forceManual: Bool
    }

    /// "Couldn't play this source": the engine's reason and the stream "Try Next Source" plays.
    private struct ManualFailureAlert: Identifiable {
        let id = UUID()
        let reason: String
        let next: StreamItem?
        /// `PlaybackContext.attempt` for the next try.
        let attempt: Int
        /// The same stream on the other engine ("Try with mpv" / "Try Native Player"); nil when
        /// the other engine cannot take it.
        let retry: PlaybackContext?
        let retryEngine: PlaybackEngine?
    }
}

/// Attaches the "play somewhere else" context menu only when at least one supported external
/// player is installed (FEAT-5). A conditional modifier rather than an inline `.contextMenu` so
/// the no-players case adds NOTHING to the row — an empty context menu would still swallow the
/// long-press and show a blank platter, which reads as broken.
///
/// The menu always offers the destinations plain Select does NOT: with the built-in player as
/// default it lists the external players; with an external default it lists "Play in NuvioTV
/// Player" first (the escape hatch back) plus any other installed externals. The default player
/// itself is omitted — Select already goes there, and a menu entry duplicating Select reads as
/// two different actions.
private struct ExternalPlayMenu: ViewModifier {
    let players: [ExternalPlayerApp]
    /// The validated default external player id, or nil when the built-in player is default.
    let defaultPlayerId: String?
    let onExternal: (ExternalPlayerApp) -> Void
    let onBuiltIn: () -> Void

    func body(content: Content) -> some View {
        if players.isEmpty {
            content
        } else {
            content.contextMenu {
                if defaultPlayerId != nil {
                    Button {
                        onBuiltIn()
                    } label: {
                        Label("Play in NuvioTV Player", systemImage: "play.tv")
                    }
                }
                ForEach(players.filter { $0.id != defaultPlayerId }, id: \.id) { player in
                    Button {
                        onExternal(player)
                    } label: {
                        Label("Open in \(player.name)", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
    }
}

/// BUG-185 (Steven rc9): the fallback if a disabled-animations Transaction on the cover binding
/// still lets the player cover slide down. `-debug.pickerCloseUIKitNoAnim YES` (read per close,
/// any build) also turns UIKit animations off from the binding's setter until the player cover's
/// `onDismiss`, with a 1 s watchdog so a dismiss that never reports cannot leave the whole app
/// unanimated.
@MainActor
enum StreamPickerCloseAnimation {
    static var uiKitFallback: Bool { UserDefaults.standard.bool(forKey: "debug.pickerCloseUIKitNoAnim") }

    private static var suspended = false
    private static var generation = 0

    static func suspendUIKitAnimations() {
        suspended = true
        generation += 1
        let mine = generation
        UIView.setAnimationsEnabled(false)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard suspended, generation == mine else { return }
            print("[StreamPicker] BUG-185 UIKit animation watchdog fired (no onDismiss within 1 s)")
            resumeUIKitAnimations()
        }
    }

    static func resumeUIKitAnimations() {
        guard suspended else { return }
        suspended = false
        UIView.setAnimationsEnabled(true)
    }
}

/// BUG-174 / BUG-183 (Steven rc7): the stream picker's loading cover and what a closing player
/// leads to. Pure, so `StreamPickerExitPolicyTests` pins every case.
enum StreamPickerCoverPolicy {
    typealias Phase = FirstPlayAutoPlayController.Phase

    /// The cover is over the list: held (an auto pick's player being presented or up, the Up Next
    /// failover picker up, the picker closing), auto mode armed but not started yet (the first
    /// frame, before `onAppear` arms the controller), or auto mode working — except a failover
    /// walk, which resolves behind the open player.
    static func showsCover(armed: Bool, phase: Phase, isFailoverWalk: Bool, held: Bool) -> Bool {
        if held { return true }
        return message(armed: armed, phase: phase, isFailoverWalk: isFailoverWalk) != nil
    }

    /// The cover's spoken label while auto mode works ("Finding the best source…"); nil otherwise.
    static func message(armed: Bool, phase: Phase, isFailoverWalk: Bool) -> String? {
        if phase == .idle { return armed ? FirstPlayAutoPlayController.Policy.overlayMessage(for: .searching) : nil }
        guard !isFailoverWalk else { return nil }
        return FirstPlayAutoPlayController.Policy.overlayMessage(for: phase)
    }
}

enum StreamPickerExitPolicy {
    enum AfterPlayer: Equatable {
        /// "Couldn't play this source" (a manual pick failed): the picker stays on its list.
        case raiseAlert
        /// The Up Next episode's source failed: its own picker opens over this one.
        case openFailoverPicker
        /// An auto walk ended with nothing during a failover: the list shows with a toast.
        case keepList
        /// D1: everything else — the picker closes with the player.
        case closePicker
    }

    static func afterPlayerClosed(alertQueued: Bool, failoverPickerQueued: Bool, listRequested: Bool) -> AfterPlayer {
        if alertQueued { return .raiseAlert }
        if failoverPickerQueued { return .openFailoverPicker }
        if listRequested { return .keepList }
        return .closePicker
    }
}

/// D5 (Steven rc7): the subtitles an external player is handed — the stream's own first, then the
/// add-on subtitles this app fetched, the viewer's preferred subtitle language(s) first, each URL
/// once, at most `cap`. The players' URL builders apply their own rules after this
/// (`ExternalPlayerPlatform.apple.kt`: VLC and VidHub take the first, Native Player keeps http(s)
/// SRT only), so the order is what matters.
enum ExternalSubtitleHandOff {
    struct Item: Equatable {
        let url: String
        let name: String
        let lang: String
    }

    static let cap = 10
    /// The longest a hand-off waits for an add-on subtitle fetch that has not finished.
    static let waitSeconds: TimeInterval = 1.5

    /// Pure. `matches(trackLanguage, target)` is the shared `languageMatchesPreference` live.
    static func merge(own: [Item], addon: [Item], preferredTargets: [String],
                      matches: (String, String) -> Bool, cap: Int = cap) -> [Item] {
        func rank(_ lang: String) -> Int {
            preferredTargets.firstIndex { matches(lang, $0) } ?? preferredTargets.count
        }
        struct Ranked { let offset: Int; let item: Item; let rank: Int }
        var ranked: [Ranked] = []
        for (offset, item) in addon.enumerated() {
            ranked.append(Ranked(offset: offset, item: item, rank: rank(item.lang)))
        }
        ranked.sort { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.offset < rhs.offset
        }
        let rankedAddon: [Item] = ranked.map { $0.item }
        var seen = Set<String>()
        var out: [Item] = []
        for item in own + rankedAddon {
            guard out.count < cap else { break }
            let key = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(item)
        }
        return out
    }

    /// The add-on subtitles for this title: the picker's prefetch (`fetchAddonSubtitles` is a no-op
    /// when that fetch already covers it), waited for at most `waitSeconds` when still running,
    /// then whatever has arrived. "Show only preferred languages" applies, as in both players.
    @MainActor
    static func liveAddonSubtitles(type: String, videoId: String) async -> [AddonSubtitle] {
        let repository = SubtitleRepository.shared
        repository.fetchAddonSubtitles(type: type, videoId: videoId)
        let key = repository.requestKey(type: type, videoId: videoId)
        let deadline = Date().addingTimeInterval(waitSeconds)
        while (repository.completedRequest.value_ as? String) != key, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let subtitles = repository.addonSubtitles.value_ as? [AddonSubtitle] ?? []
        guard let settings = playerSettings() else { return subtitles }
        return PlayerTrackSelectionKt.filterAddonSubtitlesForSettings(subtitles: subtitles, settings: settings)
    }

    /// The request's `subtitles` for `stream` plus `addonSubtitles`, ordered by the viewer's
    /// subtitle language preference (the targets both players resolve).
    @MainActor
    static func requestSubtitles(stream: StreamItem, addonSubtitles: [AddonSubtitle]) -> [SubtitleInput] {
        let own = stream.externalSubtitles.map { sub in
            Item(url: sub.url, name: { let n: String? = sub.name; return n }() ?? sub.language, lang: sub.language)
        }
        let addon = addonSubtitles.map { Item(url: $0.url, name: $0.display, lang: $0.language) }
        let targets: [String] = playerSettings().map {
            PlayerTrackSelectionKt.preferredSubtitleTargetsForSettings(settings: $0)
        } ?? []
        return merge(own: own, addon: addon, preferredTargets: targets) { track, target in
            PlayerLanguagePreferencesKt.languageMatchesPreference(trackLanguage: track, targetLanguage: target)
        }
        .map { SubtitleInput(url: $0.url, name: $0.name, lang: $0.lang) }
    }

    @MainActor
    private static func playerSettings() -> PlayerSettingsUiState? {
        PlayerSettingsRepository.shared.ensureLoaded()
        return PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState
    }
}
