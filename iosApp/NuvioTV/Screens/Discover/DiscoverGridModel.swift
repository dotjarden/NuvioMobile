import Combine
import Foundation
import SharedCore

// FEAT-73 (Steven rc4, decision D11): Discover becomes GRID-FIRST. The page a viewer lands on (the
// Own Tab root, and the Under Search push) is one paging poster grid of a single catalog + genre,
// picked from a pill band (Type · Genre · Catalog · Browse). The per-genre stage rows
// (`DiscoverRowsPage`) stay, one push away behind the Browse pill.
//
//     AddonRepository.uiState ──watch──► DiscoverSources.options(addons:)      (shared, pure, C5)
//                                          │ signature unchanged → nothing
//                                          ▼
//     selection: type → catalog (DiscoverSources.gridDefaultCatalog, a persisted pick wins)
//                       → genre (the per-catalog memory, C4: DiscoverSelectionStorage.loadGenre)
//                                          │
//                                          ▼
//     page 0 ──fetchCatalogPageChecked(skip: nil)──► items ──itemAppeared(≥ n − 8)──► page k (skip)
//                                                    (mergeCatalogItems + nextCatalogPaginationState,
//                                                     the rules CatalogRepository pages with)
//
// Like `DiscoverRowsViewModel`, it never touches the `CatalogRepository` or `SearchRepository`
// singletons (one active request each; Home and the See All grid use them). Every page goes
// through the `@Throws` bridge and Search's Discover filters (`DiscoverRowsPlan.displayItems`).
// A selection change cancels the Swift task in flight and bumps the generation, so a late page
// never lands on the new selection (the Kotlin request underneath runs to its end).

// MARK: - Plan (pure)

/// The pure half of the grid page, pinned by `DiscoverGridPlanTests`.
nonisolated enum DiscoverGridPlan {
    /// The Genre pill's "All" value (genre names are never blank: `DiscoverRowsPlan.specs` and
    /// the add-on manifests drop them).
    static let allGenre = ""
    /// Load the next page when a tile this close to the end appears (the See All grid's rule).
    static let loadMoreThreshold = 8
    /// Consecutive pages whose items were all filtered out (hide-unreleased) before the grid
    /// stops pulling more by itself to find something to show.
    static let emptyPageAdvanceLimit = 3
    /// `maxItems` for a grid page: no cap (the catalog's own page size decides; `fetchCatalogPage`
    /// counts `rawItemCount` before the cap, so a capped page would skip titles).
    static let pageMaxItems = Int32.max
    /// `CATALOG_PAGE_SIZE` (shared `CatalogData.kt`): a page this full pages even when the manifest
    /// doesn't declare `skip`, as `CatalogRepository` does.
    static let fullPageSize = 100

    /// The Genre pill's choices: nil = no pill (the catalog has no genres). An optional genre
    /// offers "All" first; a required one only its genres.
    static func genreChoices(_ option: DiscoverCatalogOption) -> [String]? {
        let genres = option.genreOptions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !genres.isEmpty else { return nil }
        return option.genreRequired ? genres : [allGenre] + genres
    }

    /// The pill value for a selection genre (nil = "All").
    static func pillValue(_ genre: String?) -> String { genre ?? allGenre }

    /// The selection genre for a pill value ("All" = nil).
    static func genre(fromPill value: String) -> String? { value == allGenre ? nil : value }

    static func genreLabel(_ value: String) -> String {
        value == allGenre ? String(localized: "All") : value
    }

    /// The genre `option` can actually fetch with: `requested` when the catalog offers it, else
    /// nil for an optional genre ("All") or the first genre for a required one.
    static func resolvedGenre(_ requested: String?, for option: DiscoverCatalogOption) -> String? {
        guard let choices = genreChoices(option) else { return nil }
        if let requested, requested != allGenre, choices.contains(requested) { return requested }
        return option.genreRequired ? choices.first : nil
    }

    /// The grid's identity: its `.id` (a new selection starts at the top) and the probe's tokens.
    static func gridKey(type: String, catalogKey: String, genre: String?) -> String {
        "\(type)|\(catalogKey)|\(genre ?? "*")"
    }

    /// The tile at `index` of `count` is close enough to the end to load the next page.
    static func shouldLoadMore(index: Int, count: Int) -> Bool {
        index >= count - loadMoreThreshold
    }

    /// The pagination rule (`CatalogRepository`'s): pages when the manifest declares `skip` or the
    /// page was full.
    static func supportsPagination(option: DiscoverCatalogOption, rawItemCount: Int) -> Bool {
        option.supportsPagination || rawItemCount >= fullPageSize
    }
}

/// The grid's content state for one selection.
nonisolated enum DiscoverGridPhase: Equatable, Sendable {
    case loading
    case loaded
    /// Settled with no titles.
    case empty
    /// The first page failed (a later page failing keeps the titles and stops paging).
    case failed

    var token: String {
        switch self {
        case .loading: return "loading"
        case .loaded: return "loaded"
        case .empty: return "empty"
        case .failed: return "failed"
        }
    }
}

// MARK: - Services

/// What the grid view model fetches and persists through, injectable (as `DiscoverRowsServices`)
/// so the tests run without the network or the profile's stored selection.
struct DiscoverGridServices {
    /// One page of `option` + `genre` from `skip` (nil = the first page). The returned page's
    /// `items` are already through Search's Discover filters; `rawItemCount` and `nextSkip` are
    /// the add-on's, for the pagination rule.
    let fetch: @MainActor (_ option: DiscoverCatalogOption, _ genre: String?, _ skip: Int?,
                           _ forceRefresh: Bool) async throws -> CatalogPage
    /// The catalog to open `type` on (nil = the first option's type): `gridDefaultCatalog`.
    let defaultCatalogKey: @MainActor (_ options: [DiscoverCatalogOption], _ type: String?) -> String?
    /// The genre remembered for `option` (C4), resolved against its genre list.
    let rememberedGenre: @MainActor (_ option: DiscoverCatalogOption) -> String?
    /// Persists an explicit pick: the catalog key (shared with Search's Discover and the Browse
    /// rows) and that catalog's genre.
    let save: @MainActor (_ option: DiscoverCatalogOption, _ genre: String?) -> Void

    static let live = DiscoverGridServices(
        fetch: { option, genre, skip, forceRefresh in
            let page = try await CatalogDataBridgingKt.fetchCatalogPageChecked(
                manifestUrl: option.manifestUrl,
                type: option.type,
                catalogId: option.catalogId,
                genre: genre,
                maxItems: DiscoverGridPlan.pageMaxItems,
                forceRefresh: forceRefresh,
                skip: skip.map { KotlinInt(int: Int32($0)) }
            )
            CustomPosterUrlRepository.shared.ensureLoaded()
            let pattern = CustomPosterUrlRepository.shared.patternForScreen(screen: .search)
            let items = DiscoverRowsPlan.displayItems(
                page.items,
                hideUnreleased: HomeCatalogSettingsRepository.shared.snapshot().hideUnreleasedContent,
                todayIsoDate: CurrentDateProvider.shared.todayIsoDate(),
                nowEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                posterPattern: pattern
            )
            return CatalogPage(items: items, rawItemCount: page.rawItemCount, nextSkip: page.nextSkip)
        },
        defaultCatalogKey: { options, type in
            DiscoverSources.shared.gridDefaultCatalog(options: options, type: type)?.key
        },
        rememberedGenre: { option in
            DiscoverSources.shared.gridGenre(option: option)
        },
        save: { option, genre in
            DiscoverSources.shared.saveGridSelection(option: option, genre: genre)
        }
    )
}

// MARK: - View model

/// See the file header.
@MainActor
final class DiscoverGridViewModel: ObservableObject {
    /// The grid's titles for the selection, merged across pages.
    @Published private(set) var items: [MetaPreview] = []
    @Published private(set) var phase: DiscoverGridPhase = .loading
    /// A next page is in flight (the spinner under the grid).
    @Published private(set) var isLoadingMore = false
    @Published private(set) var selectedType: String?
    @Published private(set) var selectedCatalogKey: String?
    /// nil = "All" (or a catalog without genres).
    @Published private(set) var selectedGenre: String?
    /// `DiscoverGridPlan.gridKey`; "" with no selection. The page's grid is `.id`'d on it.
    @Published private(set) var gridKey = ""
    @Published private(set) var typeOptions: [String] = []
    @Published private(set) var options: [DiscoverCatalogOption] = []
    /// Why there is no selection (`.ready` once there is one).
    @Published private(set) var sourcesState: DiscoverSourcesState = .waiting

    private let services: DiscoverGridServices
    private var nextSkip: Int?
    private var consecutiveDuplicatePages: Int32 = 0
    private var emptyPageAdvances = 0
    private var inFlight: Task<Void, Never>?
    /// The in-flight fetch's kind, so a `stop()` that cancelled it knows what to resume.
    private var inFlightIsFirstPage = false
    private var generation = 0
    /// The last catalog picked per type this session, so Type › Series → Movies returns to it.
    private var catalogByType: [String: String] = [:]
    private var optionsSignature: String?

    private var addonWatcher: FlowWatcher?
    private var started = false
    /// As `DiscoverRowsViewModel.stopped` (BUG-47 H2): drops a late watcher value, parks fetches.
    private var stopped = false
    /// A `stop()` cancelled a fetch: the next `start()` runs it again.
    private var resumeFirstPage = false
    private var resumeNextPage = false

    /// nil = `.live` (a default argument would be evaluated off the main actor).
    init(services: DiscoverGridServices? = nil) {
        self.services = services ?? .live
    }

    var selectedOption: DiscoverCatalogOption? {
        selectedCatalogKey.flatMap { key in options.first { $0.key == key } }
    }

    /// The Catalog pill's choices for `type`.
    func catalogOptions(for type: String) -> [DiscoverCatalogOption] {
        DiscoverRowsPlan.catalogs(ofType: type, in: options)
    }

    var canLoadMore: Bool { nextSkip != nil }

    // MARK: Lifecycle

    /// Attaches the add-on watcher and resumes a fetch a `stop()` cancelled. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        stopped = false
        addonWatcher = FlowWatcherKt.watch(AddonRepository.shared.uiState) { [weak self] emitted in
            guard let self, !self.stopped else { return }
            guard let state = emitted as? AddonsUiState else { return }
            self.addonsChanged(state)
        }
        AddonRepository.shared.initialize()
        if resumeFirstPage {
            resumeFirstPage = false
            loadFirstPage(forceRefresh: false)
        } else if resumeNextPage {
            resumeNextPage = false
            loadMore()
        }
    }

    /// Detaches the watcher and cancels the fetch in flight; titles and selection are kept.
    func stop() {
        stopped = true
        addonWatcher?.cancel()
        addonWatcher = nil
        started = false
        if inFlight != nil {
            if inFlightIsFirstPage { resumeFirstPage = true } else { resumeNextPage = true }
        }
        cancelInFlight(reason: "stop")
        if isLoadingMore { isLoadingMore = false }
    }

    // MARK: Sources

    private func addonsChanged(_ state: AddonsUiState) {
        let addons = state.addons
        let enabled = AddonModelsKt.enabledAddons(addons)
        let options = DiscoverSources.shared.options(addons: addons)
        applySources(
            options: options,
            state: DiscoverRowsPlan.sourcesState(
                isInitialized: state.isInitialized,
                hasEnabledAddons: !enabled.isEmpty,
                manifestsPending: AddonModelsKt.hasPendingEnabledManifests(addons),
                manifestError: AddonModelsKt.firstEnabledManifestError(addons),
                hasEnabledManifest: enabled.contains { $0.manifest != nil },
                optionCount: options.count
            )
        )
    }

    /// One add-on snapshot's Discover catalogs. An unchanged list keeps everything; a changed one
    /// keeps the selection when its catalog is still offered (re-fetching only when the catalog's
    /// own entry changed), else opens the default. Internal for the tests.
    func applySources(options: [DiscoverCatalogOption], state: DiscoverSourcesState) {
        if sourcesState != state { sourcesState = state }
        let signature = DiscoverRowsPlan.optionsSignature(options)
        guard signature != optionsSignature else { return }
        let previous = selectedOption
        optionsSignature = signature
        self.options = options
        let types = DiscoverRowsPlan.types(options)
        if typeOptions != types { typeOptions = types }

        guard !options.isEmpty else {
            clearSelection()
            return
        }
        if let previous, let kept = options.first(where: { $0.key == previous.key }) {
            let genre = DiscoverGridPlan.resolvedGenre(selectedGenre, for: kept)
            let unchanged = DiscoverRowsPlan.optionsSignature([kept]) == DiscoverRowsPlan.optionsSignature([previous])
            if unchanged, genre == selectedGenre { return }
            activate(kept, genre: genre, reason: "sources")
            return
        }
        guard let option = defaultOption(type: selectedType) ?? defaultOption(type: nil) else {
            clearSelection()
            return
        }
        activate(option, genre: services.rememberedGenre(option), reason: "sources")
    }

    private func defaultOption(type: String?) -> DiscoverCatalogOption? {
        services.defaultCatalogKey(options, type).flatMap { key in options.first { $0.key == key } }
    }

    // MARK: Picks

    /// Type pill: the catalog last used for that type this session, else the type's default.
    /// A Type pick alone persists nothing (the default is not an explicit pick).
    func select(type: String) {
        guard type != selectedType else { return }
        let candidates = catalogOptions(for: type)
        guard let option = catalogByType[type].flatMap({ key in candidates.first { $0.key == key } })
            ?? defaultOption(type: type)
            ?? candidates.first else { return }
        activate(option, genre: services.rememberedGenre(option), reason: "type")
    }

    /// Catalog pill: an explicit pick, persisted with that catalog's remembered genre.
    func select(catalogKey: String) {
        guard catalogKey != selectedCatalogKey,
              let option = options.first(where: { $0.key == catalogKey }) else { return }
        let genre = services.rememberedGenre(option)
        services.save(option, genre)
        activate(option, genre: genre, reason: "catalog")
    }

    /// Genre pill (`DiscoverGridPlan.allGenre` = "All"): persisted per catalog.
    func select(genrePill value: String) {
        guard let option = selectedOption else { return }
        let genre = DiscoverGridPlan.resolvedGenre(DiscoverGridPlan.genre(fromPill: value), for: option)
        guard genre != selectedGenre else { return }
        services.save(option, genre)
        activate(option, genre: genre, reason: "genre")
    }

    private func activate(_ option: DiscoverCatalogOption, genre: String?, reason: String) {
        cancelInFlight(reason: reason)
        resumeFirstPage = false
        resumeNextPage = false
        catalogByType[option.type] = option.key
        let genre = DiscoverGridPlan.resolvedGenre(genre, for: option)
        if selectedType != option.type { selectedType = option.type }
        if selectedCatalogKey != option.key { selectedCatalogKey = option.key }
        if selectedGenre != genre { selectedGenre = genre }
        let key = DiscoverGridPlan.gridKey(type: option.type, catalogKey: option.key, genre: genre)
        if gridKey != key { gridKey = key }
        NSLog("[DiscoverGrid] select type=%@ catalog=%@ genre=%@ reason=%@",
              option.type, option.key, genre ?? "*", reason)
        loadFirstPage(forceRefresh: false)
    }

    private func clearSelection() {
        cancelInFlight(reason: "nosources")
        resumeFirstPage = false
        resumeNextPage = false
        nextSkip = nil
        if !items.isEmpty { items = [] }
        if phase != .loading { phase = .loading }
        if isLoadingMore { isLoadingMore = false }
        if selectedType != nil { selectedType = nil }
        if selectedCatalogKey != nil { selectedCatalogKey = nil }
        if selectedGenre != nil { selectedGenre = nil }
        if !gridKey.isEmpty { gridKey = "" }
    }

    // MARK: Paging

    /// The failed state's Try Again. With no selection (the add-ons themselves failed), the add-on
    /// manifests are refreshed instead.
    func retry() {
        guard selectedOption != nil else {
            AddonRepository.shared.refreshAll()
            return
        }
        loadFirstPage(forceRefresh: true)
    }

    /// A tile appeared: page when it is within `loadMoreThreshold` of the end.
    func itemAppeared(at index: Int) {
        guard DiscoverGridPlan.shouldLoadMore(index: index, count: items.count) else { return }
        loadMore()
    }

    private func loadFirstPage(forceRefresh: Bool) {
        guard let option = selectedOption else { return }
        cancelInFlight(reason: "reload")
        nextSkip = nil
        consecutiveDuplicatePages = 0
        emptyPageAdvances = 0
        if !items.isEmpty { items = [] }
        if phase != .loading { phase = .loading }
        if isLoadingMore { isLoadingMore = false }
        guard !stopped else {
            resumeFirstPage = true
            return
        }
        launch(option, genre: selectedGenre, skip: 0, forceRefresh: forceRefresh)
    }

    private func loadMore() {
        guard !stopped, inFlight == nil, phase == .loaded || phase == .empty,
              let skip = nextSkip, let option = selectedOption else { return }
        isLoadingMore = true
        launch(option, genre: selectedGenre, skip: skip, forceRefresh: false)
    }

    private func launch(_ option: DiscoverCatalogOption, genre: String?, skip: Int, forceRefresh: Bool) {
        let token = generation
        let fetch = services.fetch
        inFlightIsFirstPage = skip == 0
        inFlight = Task { [weak self] in
            let result: Result<CatalogPage, Error>
            do {
                result = .success(try await fetch(option, genre, skip > 0 ? skip : nil, forceRefresh))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            self?.finish(option: option, skip: skip, token: token, result: result)
        }
    }

    private func finish(option: DiscoverCatalogOption, skip: Int, token: Int, result: Result<CatalogPage, Error>) {
        guard token == generation, inFlight != nil else { return }
        inFlight = nil
        if isLoadingMore { isLoadingMore = false }
        let reset = skip == 0
        switch result {
        case .failure(let error):
            NSLog("[DiscoverGrid] page failed catalog=%@ skip=%d error=%@", option.key, skip, String(describing: error))
            nextSkip = nil
            if reset { phase = .failed }
        case .success(let page):
            let merged = reset
                ? CatalogDataKt.dedupeCatalogItems(items: page.items)
                : CatalogDataKt.mergeCatalogItems(existing: items, incoming: page.items)
            // Review r1 (P3): a page the hide-unreleased filter emptied still brought new RAW titles;
            // counting it as a duplicate stopped paging for good after three such pages.
            let filteredAll = page.items.isEmpty && page.rawItemCount > 0
            let countBefore = items.count
            let loadedNewItems = reset || merged.count > countBefore || filteredAll
            let state = CatalogDataKt.nextCatalogPaginationState(
                supportsPagination: DiscoverGridPlan.supportsPagination(option: option,
                                                                        rawItemCount: Int(page.rawItemCount)),
                requestedSkip: Int32(skip),
                page: page,
                loadedNewItems: loadedNewItems,
                consecutiveDuplicatePages: reset ? 0 : consecutiveDuplicatePages
            )
            nextSkip = state.nextSkip.map { Int(truncating: $0) }
            consecutiveDuplicatePages = state.consecutiveDuplicatePages
            if merged.count != items.count || reset { items = merged }
            let newPhase: DiscoverGridPhase = merged.isEmpty ? .empty : .loaded
            if phase != newPhase { phase = newPhase }
            // A page the unreleased filter emptied: pull the next one (bounded), so a catalog
            // whose first titles are all upcoming still shows something.
            // Review r1 (P3): also when the grid has titles but this page added none (no new tile
            // appears to trigger the next load).
            let addedNone = merged.isEmpty || (!reset && merged.count == countBefore)
            // The refill budget is per run of empty pages, not per selection.
            if !addedNone { emptyPageAdvances = 0 }
            if addedNone, nextSkip != nil, emptyPageAdvances < DiscoverGridPlan.emptyPageAdvanceLimit {
                emptyPageAdvances += 1
                loadMore()
            }
        }
    }

    private func cancelInFlight(reason: String) {
        generation &+= 1
        guard let task = inFlight else { return }
        NSLog("[DiscoverGrid] cancel reason=%@", reason)
        task.cancel()
        inFlight = nil
    }
}
