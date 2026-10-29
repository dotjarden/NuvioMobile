import SwiftUI
import SharedCore

/// One discovery destination. Keep the Home-based browsing surface mounted while a committed
/// query presents results, preserving filter selection, row expansion and scroll positions.
struct SearchView: View {
    let home: HomeViewModel
    @StateObject private var model = SearchViewModel()
    @State private var draftQuery = ""
    @State private var query = ""
    @State private var resultType = "All titles"
    @State private var resultCatalog: String? = nil
    @State private var resultGenre = "All genres"
    @State private var resultSort = "Recommended"
    @Environment(\.posterStyle) private var posterStyle
    @Environment(\.tabBarVisibility) private var visibility
    /// Upstream's Discover placement setting, read once per tab tree. Off hides the browse surface
    /// (the synced Hide Discover preference maps to it).
    @Environment(\.discoverPlacementResolved) private var discoverPlacement
    @FocusState private var resultsFieldFocused: Bool
    @State private var restoreBrowseFocus = 0

    private var isSearching: Bool { !query.isEmpty }
    private var hidesBrowse: Bool { discoverPlacement == .off }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: posterStyle.width + Theme.Spacing.rowGap), spacing: Theme.Spacing.rowGap)]
    }

    var body: some View {
        ZStack {
            MediaBrowseView(model: home, mediaType: "movie",
                            searchControls: AnyView(searchEntry(width: 330, identifier: "search.query")),
                            restoreSearchFocus: restoreBrowseFocus)
                .opacity(isSearching || hidesBrowse ? 0 : 1)
                .disabled(isSearching || hidesBrowse)
                .allowsHitTesting(!isSearching && !hidesBrowse)
                .accessibilityHidden(isSearching || hidesBrowse)

            if !isSearching && hidesBrowse {
                // Respect Nuvio's synced Hide Discover preference after merging the tabs.
                ZStack {
                    Theme.Palette.background.ignoresSafeArea()
                    VStack(alignment: .leading) {
                        searchEntry(width: 630, identifier: "search.query")
                        Spacer()
                    }.padding(Theme.Spacing.screen)
                }.railMenuReveal()
            }
            if isSearching {
                resultsPage
            }
        }
        .onAppear {
            model.start()
            visibility.setSearchResultsActive(isSearching || hidesBrowse)
        }
        .onDisappear {
            model.stop()
            visibility.setSearchResultsActive(false)
        }
        .onChange(of: hidesBrowse) { _, hidden in
            visibility.setSearchResultsActive(isSearching || hidden)
        }
        .onChange(of: isSearching) { _, active in
            visibility.setSearchResultsActive(active || hidesBrowse)
            if active {
                DispatchQueue.main.async { resultsFieldFocused = true }
            } else {
                restoreBrowseFocus += 1
            }
        }
    }

    private func searchEntry(width: CGFloat, identifier: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search movies & shows", text: $draftQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 26))
                .frame(width: width)
                .accessibilityIdentifier(identifier)
                // Commit only after the native keyboard closes. Hiding its source field
                // during typing can tear down tvOS's keyboard before the query is finished.
                .onSubmit { commitSearch(draftQuery) }
            if !model.history.isEmpty {
                Menu {
                    ForEach(model.history, id: \.self) { item in
                        Button(item) { commitSearch(item) }
                    }
                    Divider()
                    Menu("Remove from history") {
                        ForEach(model.history, id: \.self) { item in
                            Button(item, role: .destructive) { model.removeHistory(item) }
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 23)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Recent Searches")
                .accessibilityIdentifier("search.recent")
            }
        }
    }

    private var resultsPage: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 28) {
                        searchEntry(width: 630, identifier: "search.results.query")
                            .focused($resultsFieldFocused)
                        Button {
                            commitSearch("")
                        } label: {
                            Label("Clear Search", systemImage: "xmark")
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("search.clear")
                        Spacer(minLength: 0)
                    }.focusSection()

                    HStack(spacing: 24) {
                        TVSelectionMenu(title: "Content type", value: resultType,
                                        options: ["All titles", "Movies", "Shows"]) { resultType = $0 }
                        TVSelectionMenu(title: "Genre", value: resultGenre,
                                        options: ["All genres"] + resultGenres) { resultGenre = $0 }
                        TVSelectionMenu(title: "Catalog", value: selectedCatalogLabel,
                                        options: ["All catalogs"] + model.rows.map(catalogLabel)) { label in
                            resultCatalog = model.rows.first { catalogLabel($0) == label }?.key
                        }
                        TVSelectionMenu(title: "Sort", value: resultSort,
                                        options: ["Recommended", "A–Z", "Highest rated"]) { resultSort = $0 }
                        if resultType != "All titles" || resultGenre != "All genres" || resultCatalog != nil || resultSort != "Recommended" {
                            Button("Reset") { resetResultFilters() }.buttonStyle(.glass)
                        }
                        Spacer()
                        if !model.isLoading {
                            Text("\(results.count) titles").font(.caption).foregroundStyle(.secondary)
                        }
                    }.focusSection()

                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 28) {
                            resultStatus
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                                ForEach(results, id: \.key) { hit in
                                    NavigationLink(value: TitleRoute(preview: hit.item)) {
                                        PosterCard(title: hit.item.name, imageURL: hit.item.poster)
                                    }
                                    .cardFocusButtonStyle().posterButtonShape()
                                    .accessibilityIdentifier("search.result.\(hit.key)")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                    }
                    .scrollClipDisabled()
                    .reportsScrollToTabBar(tab: "Search")
                    .railMenuReveal()
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, 34)
            }
            .navigationDestination(for: TitleRoute.self) { DetailView(preview: $0.preview) }
        }
    }

    @ViewBuilder private var resultStatus: some View {
        if model.isLoading {
            HStack(spacing: 18) {
                ProgressView()
                Text("Searching…").foregroundStyle(.secondary)
            }
        } else if case .manifestFailure(let error) = model.emptyState {
            VStack(alignment: .leading, spacing: 24) {
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { model.retrySearch() }.buttonStyle(.glass)
            }
        } else if results.isEmpty {
            Text(model.emptyState?.copy ?? String(localized: "No titles match these filters."))
                .foregroundStyle(.secondary)
        }
    }

    private func catalogLabel(_ section: HomeCatalogSection) -> String {
        section.title + " · " + section.addonName
    }
    private var selectedCatalogLabel: String {
        model.rows.first { $0.key == resultCatalog }.map(catalogLabel) ?? "All catalogs"
    }
    private var resultGenres: [String] {
        Array(Set(model.rows.flatMap(\.items).flatMap(\.genres))).sorted()
    }

    private struct SearchHit {
        let item: MetaPreview
        var key: String { item.type + ":" + item.id }
    }

    private var results: [SearchHit] {
        var seen = Set<String>()
        let items = model.rows.filter { resultCatalog == nil || $0.key == resultCatalog }
            .flatMap(\.items).filter { item in
                (resultType == "All titles" || item.type == (resultType == "Movies" ? "movie" : "series"))
                    && (resultGenre == "All genres" || item.genres.contains { $0.localizedCaseInsensitiveCompare(resultGenre) == .orderedSame })
                    && seen.insert(item.type + ":" + item.id).inserted
            }
        let sorted: [MetaPreview]
        switch resultSort {
        case "A–Z": sorted = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case "Highest rated": sorted = items.sorted { (Double($0.imdbRating ?? "") ?? 0) > (Double($1.imdbRating ?? "") ?? 0) }
        default: sorted = items
        }
        return sorted.map { SearchHit(item: $0) }
    }

    private func resetResultFilters() {
        resultType = "All titles"
        resultGenre = "All genres"
        resultCatalog = nil
        resultSort = "Recommended"
    }

    private func commitSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draftQuery = trimmed
        query = trimmed
        resetResultFilters()
        model.queryChanged(trimmed)
        if !trimmed.isEmpty { model.recordSearch(trimmed) }
    }
}

/// Batch P (P9, BUG-195, probe only): `-debug.searchOpenProbe YES` (launch-latched, readable in
/// Release) logs `[SearchOpen] appear|firstBody|keyboard t=<systemUptime>` once per tab visit. The
/// rail's `[NavRail] select tab=1` line is t0; the main session measures the gap on the rig (first
/// and second visit) and then picks the fix. No behaviour change.
@MainActor
enum SearchOpenProbe {
    nonisolated static let enabled = UserDefaults.standard.bool(forKey: "debug.searchOpenProbe")
    private static var firstBodyLogged = false
    private static var keyboardLogged = false

    /// The tab appeared. Log only: `onAppear` runs AFTER the first `SearchContent.body`, so re-arming
    /// here would log `firstBody` twice on a first visit and miss it on later ones (review r1 P3-6).
    static func appear() {
        guard enabled else { return }
        log("appear")
    }

    /// The tab left: re-arm both once-per-visit marks for the next visit's first body and keyboard.
    static func disappear() {
        guard enabled else { return }
        firstBodyLogged = false
        keyboardLogged = false
    }

    /// First `SearchContent.body` of the visit.
    static func firstBody() {
        guard enabled, !firstBodyLogged else { return }
        firstBodyLogged = true
        log("firstBody")
    }

    /// First time the search keyboard reports focus in the visit.
    static func keyboard() {
        guard enabled, !keyboardLogged else { return }
        keyboardLogged = true
        log("keyboard")
    }

    /// Any other mark (the rail's hand-off ladder rungs, the focus request): same probe, same clock.
    nonisolated static func mark(_ mark: String) {
        guard enabled else { return }
        NSLog("[SearchOpen] %@ t=%.3f", mark, ProcessInfo.processInfo.systemUptime)
    }

    private static func log(_ mark: String) {
        NSLog("[SearchOpen] %@ t=%.3f", mark, ProcessInfo.processInfo.systemUptime)
    }
}
