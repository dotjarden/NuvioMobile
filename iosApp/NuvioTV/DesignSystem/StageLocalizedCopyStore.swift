import Foundation
import SharedCore

/// BUG-151 (Steven rc3/rc4): the localized copy of one title (name, synopsis, genres) in the user's
/// TMDB Metadata Language, as `fetchPreviewEnrichmentChecked` returns it. A field is nil when TMDB
/// gave nothing usable for it (blank, or no genres), so applying it never replaces real text with a
/// blank.
struct StageLocalizedCopy: Equatable {
    let title: String?
    let overview: String?
    let genres: [String]?
}

/// BUG-151 (Steven rc3/rc4: "the Stage prints the catalog's English name and synopsis where Detail
/// and official Nuvio show French"). Home's light catalog list carries whatever language the add-on
/// sends (Cinemeta: English); the shared publish only localizes the hero carousel and each row's
/// leading items. This store gives the hero focus model (`HomeHeroFocusModel`, which drives the
/// Stage strip, the folder Rows page and Classic's row-focus hero panel) a cache of each title's
/// localized copy, so a commit can show the localized name, synopsis and genres from the first
/// frame.
///
/// The rule it serves: localized copy is applied AT COMMIT ONLY, when a new title takes the stage
/// and its text is new anyway (`preparedForCommit`). It never replaces text already on screen: a
/// cache miss commits the catalog copy and only starts the lookup (the result warms the next
/// commit of that title); `HomeHeroFocusModel.enrichIfNeeded` keeps gap-filling a missing synopsis
/// or genres as before; a same-title re-adopt applies the copy only when the shown item already
/// carries it (`adoptMode`). This is the BUG-42 rule (no raw-then-localized double commit) kept.
///
/// Modelled on `TitleLogoStore` (same key-with-scope, pending/request-id commit guard, 30 s failure
/// cooldown, ~200-entry cap that only drops resolved entries), plus a concurrency limit: a row's
/// warm-up asks for up to 18 titles at once, and each lookup can cost TMDB two requests (find by
/// IMDb id, then details), so at most `maxInFlight` run at a time and the rest wait in a bounded
/// queue where a commit's own request jumps ahead of row prefetches. The Kotlin service's own
/// preview cache (keyed on TMDB id + language) is shared with `TitleLogoStore`, so a title both
/// stores ask about is fetched once.
///
/// Not an `ObservableObject`: nothing renders off it directly; the focus model reads it
/// synchronously at commit time.
@MainActor
final class StageLocalizedCopyStore {
    static let shared = StageLocalizedCopyStore()

    private init() {}

    enum Entry: Equatable {
        case pending(requestId: UInt64)
        /// A finished lookup. `nil` = TMDB had nothing usable (no TMDB id, no match, all blank),
        /// remembered so it is not asked again under this scope.
        case resolved(StageLocalizedCopy?)
    }

    /// How a cached copy is applied to a preview: `.commit` replaces name, synopsis and genres with
    /// whatever localized value exists; `.gapFill` only fills a missing synopsis or empty genres and
    /// never touches the name.
    enum ApplyMode: Equatable {
        case commit
        case gapFill
    }

    enum LookupOutcome: Equatable {
        case resolved(StageLocalizedCopy?)
        case failed
    }

    /// One queued key and whether it came from a commit (front of the queue) or a row prefetch.
    struct QueuedKey: Equatable {
        let key: String
        let priority: Bool
    }

    nonisolated static let maxEntries = 200
    nonisolated static let maxInFlight = 6
    nonisolated static let maxQueued = 60
    nonisolated static let retryCooldown: TimeInterval = 30

    private struct Job {
        let type: String
        let id: String
        let requestId: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var jobs: [String: Job] = [:]
    private var queue: [QueuedKey] = []
    private var inFlight = 0
    private var lastFailureAt: [String: Date] = [:]
    private var nextRequestId: UInt64 = 0

    // MARK: - Pure decisions (covered by StageLocalizedCopyStoreTests)

    /// The cache key: the title plus every setting that changes what the lookup returns or whether
    /// it runs (Metadata Language, the TMDB switch, the Basic Info category).
    nonisolated static func key(type: String, id: String, language: String, enabled: Bool, useBasicInfo: Bool) -> String {
        "\(type)|\(id)|\(language)|\(enabled)|\(useBasicInfo)"
    }

    /// Whether a title gets a lookup at all: TMDB on with Basic Info on (the same category gate the
    /// shared enrichment and `enrichIfNeeded` use for text fields), a non-blank id, and not a
    /// collection folder (its preview is the user's own configured copy, with a synthetic id TMDB
    /// knows nothing about). Titles with no resolvable TMDB id are eligible and resolve to nil.
    nonisolated static func isEligible(type: String, id: String, enabled: Bool, useBasicInfo: Bool) -> Bool {
        guard enabled, useBasicInfo else { return false }
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if type == StageCopy.folderType && id.hasPrefix(StageCopy.folderIdScheme) { return false }
        return true
    }

    /// The localized copy from TMDB's fields: blank strings and blank genres dropped; nil when
    /// nothing usable is left.
    nonisolated static func copy(title: String?, overview: String?, genres: [String]) -> StageLocalizedCopy? {
        let cleanTitle = StageCopy.nonBlank(title)
        let cleanOverview = StageCopy.nonBlank(overview)
        let cleanGenres = genres
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard cleanTitle != nil || cleanOverview != nil || !cleanGenres.isEmpty else { return nil }
        return StageLocalizedCopy(title: cleanTitle, overview: cleanOverview, genres: cleanGenres.isEmpty ? nil : cleanGenres)
    }

    /// A finished `fetchPreviewEnrichmentChecked`: an error is a failure (cooldown, retry later,
    /// never latched as "nothing"); otherwise the copy, possibly nil.
    nonisolated static func completionOutcome(enrichment: TmdbPreviewEnrichment?, error: Error?) -> LookupOutcome {
        guard error == nil else { return .failed }
        guard let enrichment else { return .resolved(nil) }
        return .resolved(copy(title: enrichment.localizedTitle,
                              overview: enrichment.description_,
                              genres: enrichment.genres))
    }

    /// Same as `TitleLogoStore.shouldCommit`: only the exact pending attempt may write its key.
    nonisolated static func shouldCommit(entry: Entry?, requestId: UInt64) -> Bool {
        entry == .pending(requestId: requestId)
    }

    nonisolated static func shouldSkipRetry(lastFailure: Date?, now: Date, cooldown: TimeInterval) -> Bool {
        guard let lastFailure else { return false }
        return now.timeIntervalSince(lastFailure) < cooldown
    }

    /// At the cap, drop every resolved entry and keep the pending ones (a pending entry dropped
    /// here would never be asked for again, `TitleLogoStore`'s Codex r3 finding).
    nonisolated static func evictingResolved(_ entries: [String: Entry], cap: Int) -> [String: Entry] {
        guard entries.count >= cap else { return entries }
        return entries.filter { _, entry in
            if case .pending = entry { return true }
            return false
        }
    }

    /// Queue placement. A commit's request goes to the front (moved there when its key is already
    /// waiting as a prefetch); a prefetch goes to the back and is ignored when already queued. Past
    /// `limit`, the oldest prefetches (front-most non-priority keys) are dropped and returned so
    /// the caller can clear their pending entries.
    nonisolated static func enqueued(_ queue: [QueuedKey], key: String, priority: Bool, limit: Int) -> (queue: [QueuedKey], dropped: [String]) {
        var next = queue
        if let index = next.firstIndex(where: { $0.key == key }) {
            guard priority, !next[index].priority || index != 0 else { return (next, []) }
            next.remove(at: index)
            next.insert(QueuedKey(key: key, priority: true), at: 0)
        } else if priority {
            next.insert(QueuedKey(key: key, priority: true), at: 0)
        } else {
            next.append(QueuedKey(key: key, priority: false))
        }
        var dropped: [String] = []
        while next.count > limit, let index = next.firstIndex(where: { !$0.priority }) {
            dropped.append(next.remove(at: index).key)
        }
        return (next, dropped)
    }

    /// `item` with `copy` applied under `mode`. Returns `item` itself when nothing changes, so a
    /// caller's equality check (`focusedItem?.isEqual`) still reads a no-op as a no-op. Every other
    /// field is carried over unchanged.
    nonisolated static func applying(_ copy: StageLocalizedCopy?, to item: MetaPreview, mode: ApplyMode) -> MetaPreview {
        guard let copy else { return item }
        let itemDescription: String? = item.description_
        let name: String
        let description: String?
        let genres: [String]
        switch mode {
        case .commit:
            name = copy.title ?? item.name
            description = copy.overview ?? itemDescription
            genres = copy.genres ?? item.genres
        case .gapFill:
            name = item.name
            description = StageCopy.nonBlank(itemDescription) == nil ? (copy.overview ?? itemDescription) : itemDescription
            genres = item.genres.isEmpty ? (copy.genres ?? item.genres) : item.genres
        }
        guard name != item.name || description != itemDescription || genres != item.genres else { return item }
        return MetaPreview(
            id: item.id,
            type: item.type,
            name: name,
            poster: item.poster,
            banner: item.banner,
            logo: item.logo,
            posterShape: item.posterShape,
            description: description,
            releaseInfo: item.releaseInfo,
            rawReleaseDate: item.rawReleaseDate,
            popularity: item.popularity,
            voteCount: item.voteCount,
            imdbRating: item.imdbRating,
            genres: genres,
            rawPosterUrl: item.rawPosterUrl,
            landscapePoster: item.landscapePoster,
            rawLandscapePosterUrl: item.rawLandscapePosterUrl,
            customPosterApplied: item.customPosterApplied
        )
    }

    /// The mode for a same-title re-adopt (a second preview of the committed title, e.g. Continue
    /// Watching then a catalog row): `.commit` only when the item on screen already shows the
    /// localized name or synopsis (its commit was localized), so the re-adopt keeps it; otherwise
    /// `.gapFill`, so a title committed in the catalog's language never switches language on
    /// screen.
    nonisolated static func adoptMode(shown: MetaPreview?, copy: StageLocalizedCopy?) -> ApplyMode {
        guard let shown, let copy else { return .gapFill }
        // The name decides when the copy has one: a catalog-language commit whose missing
        // synopsis `enrichIfNeeded` filled in the user's language still shows the catalog name,
        // and must not switch it.
        if let title = copy.title { return shown.name == title ? .commit : .gapFill }
        let shownDescription: String? = shown.description_
        if let overview = copy.overview, shownDescription == overview { return .commit }
        return .gapFill
    }

    // MARK: - Commit-time API (HomeHeroFocusModel)

    /// The preview to commit for a title taking the stage: the cached localized copy applied in
    /// `.commit` mode, or `item` unchanged on a miss, in which case a priority lookup starts so the
    /// title's next commit has it.
    func preparedForCommit(_ item: MetaPreview) -> MetaPreview {
        guard let key = eligibleKey(for: item) else { return item }
        if case .resolved(let copy)? = entries[key] {
            return Self.applying(copy, to: item, mode: .commit)
        }
        request(type: item.type, id: item.id, key: key, priority: true)
        return item
    }

    /// The preview to adopt for a same-title re-report while `shown` is on screen (see
    /// `adoptMode`).
    func preparedForAdopt(_ item: MetaPreview, shown: MetaPreview?) -> MetaPreview {
        guard let key = eligibleKey(for: item) else { return item }
        guard case .resolved(let copy)? = entries[key] else {
            request(type: item.type, id: item.id, key: key, priority: true)
            return item
        }
        return Self.applying(copy, to: item, mode: Self.adoptMode(shown: shown, copy: copy))
    }

    /// A row's warm-up (`HomeRowPreviews.warmRow`): queue lookups for the row's leading titles
    /// behind any commit requests.
    func prefetch(_ items: [MetaPreview]) {
        let settings = TmdbSettingsRepository.shared.snapshot()
        for item in items {
            guard let key = eligibleKey(for: item, settings: settings) else { continue }
            request(type: item.type, id: item.id, key: key, priority: false)
        }
    }

    // MARK: - Lookup machinery

    private func eligibleKey(for item: MetaPreview, settings: TmdbSettings? = nil) -> String? {
        let settings = settings ?? TmdbSettingsRepository.shared.snapshot()
        guard Self.isEligible(type: item.type, id: item.id, enabled: settings.enabled, useBasicInfo: settings.useBasicInfo) else {
            return nil
        }
        return Self.key(type: item.type, id: item.id, language: settings.language,
                        enabled: settings.enabled, useBasicInfo: settings.useBasicInfo)
    }

    private func request(type: String, id: String, key: String, priority: Bool) {
        if case .pending? = entries[key] {
            // Already queued or running: a commit only moves a waiting prefetch to the front.
            if priority, jobs[key] != nil, queue.contains(where: { $0.key == key }) {
                queue = Self.enqueued(queue, key: key, priority: true, limit: Self.maxQueued).queue
            }
            return
        }
        guard entries[key] == nil else { return }
        guard !Self.shouldSkipRetry(lastFailure: lastFailureAt[key], now: Date(), cooldown: Self.retryCooldown) else { return }

        entries = Self.evictingResolved(entries, cap: Self.maxEntries)
        nextRequestId += 1
        let requestId = nextRequestId
        entries[key] = .pending(requestId: requestId)
        jobs[key] = Job(type: type, id: id, requestId: requestId)
        let placed = Self.enqueued(queue, key: key, priority: priority, limit: Self.maxQueued)
        queue = placed.queue
        for droppedKey in placed.dropped {
            // Never started: clear it so a later warm-up or commit can ask again.
            jobs.removeValue(forKey: droppedKey)
            entries.removeValue(forKey: droppedKey)
        }
        pump()
    }

    private func pump() {
        while inFlight < Self.maxInFlight, !queue.isEmpty {
            let key = queue.removeFirst().key
            guard let job = jobs.removeValue(forKey: key),
                  Self.shouldCommit(entry: entries[key], requestId: job.requestId) else { continue }
            let settings = TmdbSettingsRepository.shared.snapshot()
            // The scope moved on while this waited (language changed, TMDB or Basic Info turned
            // off): drop it; the new scope asks under its own key.
            let current = Self.isEligible(type: job.type, id: job.id, enabled: settings.enabled, useBasicInfo: settings.useBasicInfo)
                ? Self.key(type: job.type, id: job.id, language: settings.language,
                           enabled: settings.enabled, useBasicInfo: settings.useBasicInfo)
                : nil
            guard current == key else {
                entries.removeValue(forKey: key)
                continue
            }
            inFlight += 1
            start(job, key: key, settings: settings)
        }
    }

    private func start(_ job: Job, key: String, settings: TmdbSettings) {
        // The checked twin, never `fetchPreviewEnrichment`: an unchecked suspend export aborts the
        // process on any thrown failure (`TitleLogoStore.lookupOne`, FEAT-42 crash fix).
        TmdbMetadataService.shared.fetchPreviewEnrichmentChecked(
            type: job.type, id: job.id, settings: settings
        ) { [weak self] enrichment, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = max(0, self.inFlight - 1)
                defer { self.pump() }
                guard Self.shouldCommit(entry: self.entries[key], requestId: job.requestId) else { return }
                switch Self.completionOutcome(enrichment: enrichment, error: error) {
                case .failed:
                    self.entries.removeValue(forKey: key)
                    let now = Date()
                    self.lastFailureAt = self.lastFailureAt.filter { now.timeIntervalSince($0.value) < Self.retryCooldown }
                    self.lastFailureAt[key] = now
                    NSLog("[StageLocalizedCopy] lookup failed key=%@ error=%@", key, String(describing: error))
                case .resolved(let copy):
                    self.entries[key] = .resolved(copy)
                    self.lastFailureAt.removeValue(forKey: key)
                }
            }
        }
    }
}
