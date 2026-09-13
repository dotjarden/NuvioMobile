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
    @FocusState private var resultsFieldFocused: Bool
    @State private var restoreBrowseFocus = 0

    private var isSearching: Bool { !query.isEmpty }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: posterStyle.width + Theme.Spacing.rowGap), spacing: Theme.Spacing.rowGap)]
    }

    var body: some View {
        ZStack {
            MediaBrowseView(model: home, mediaType: "movie",
                            searchControls: AnyView(searchEntry(width: 330, identifier: "search.query")),
                            restoreSearchFocus: restoreBrowseFocus)
                .opacity(isSearching || model.hideDiscover ? 0 : 1)
                .disabled(isSearching || model.hideDiscover)
                .allowsHitTesting(!isSearching && !model.hideDiscover)
                .accessibilityHidden(isSearching || model.hideDiscover)

            if !isSearching && model.hideDiscover {
                // Respect Nuvio's synced Hide Discover preference after merging the tabs.
                ZStack {
                    Theme.Palette.background.ignoresSafeArea()
                    VStack(alignment: .leading) {
                        searchEntry(width: 630, identifier: "search.query")
                        Spacer()
                    }.padding(Theme.Spacing.screen)
                }.sidebarMenuReveal()
            }
            if isSearching {
                resultsPage
            }
        }
        .onAppear {
            model.start()
            visibility.setSearchResultsActive(isSearching || model.hideDiscover)
        }
        .onDisappear {
            model.stop()
            visibility.setSearchResultsActive(false)
        }
        .onChange(of: model.hideDiscover) { _, hidden in
            visibility.setSearchResultsActive(isSearching || hidden)
        }
        .onChange(of: isSearching) { _, active in
            visibility.setSearchResultsActive(active || model.hideDiscover)
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
                                        options: ["All catalogs"] + model.sections.map(catalogLabel)) { label in
                            resultCatalog = model.sections.first { catalogLabel($0) == label }?.key
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
                    .sidebarMenuReveal()
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
        } else if let error = model.searchError {
            VStack(alignment: .leading, spacing: 24) {
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { model.retrySearch() }.buttonStyle(.glass)
            }
        } else if results.isEmpty {
            Text(model.emptyMessage ?? "No titles match these filters.")
                .foregroundStyle(.secondary)
        }
    }

    private func catalogLabel(_ section: HomeCatalogSection) -> String {
        section.title + " · " + section.addonName
    }
    private var selectedCatalogLabel: String {
        model.sections.first { $0.key == resultCatalog }.map(catalogLabel) ?? "All catalogs"
    }
    private var resultGenres: [String] {
        Array(Set(model.sections.flatMap(\.items).flatMap(\.genres))).sorted()
    }

    private struct SearchHit {
        let item: MetaPreview
        var key: String { item.type + ":" + item.id }
    }

    private var results: [SearchHit] {
        var seen = Set<String>()
        let items = model.sections.filter { resultCatalog == nil || $0.key == resultCatalog }
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
