import SwiftUI
import SharedCore

/// Movie/show entry points share the existing catalog pipeline and detail/player routes.
/// Filtered catalogs use the shared paginated Discover pipeline while this tab is visible.
struct MediaBrowseView: View {
    @ObservedObject var model: HomeViewModel
    @State var mediaType: String
    @StateObject private var discovery = SearchViewModel()
    @State private var genre = "All genres"
    @State private var catalog = "All catalogs"
    @State private var order = "Recommended"
    private var selectedCatalogLabel: String {
        guard let selected = discovery.discover?.selectedCatalog else { return "Catalog" }
        return selected.catalogName + " · " + selected.addonName
    }
    private var availableGenres: [String] { discovery.discover?.genreOptions ?? [] }
    private var filtered: Bool { genre != "All genres" || catalog != "All catalogs" || order != "Recommended" }
    private var results: [MetaPreview] {
        var seen = Set<String>()
        let candidates = filtered ? (discovery.discover?.items ?? []) : sections.flatMap { $0.items }
        let items = candidates.filter {
            $0.type == mediaType && seen.insert($0.type + ":" + $0.id).inserted
        }
        if order == "A–Z" { return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        if order == "Highest rated" { return items.sorted { (Double($0.imdbRating ?? "") ?? 0) > (Double($1.imdbRating ?? "") ?? 0) } }
        return items
    }
    private var sections: [HomeCatalogSection] {
        model.sections.filter { section in section.items.contains { $0.type == mediaType } }
    }
    private var browseRows: [HomeRow] {
        if filtered, let option = discovery.discover?.selectedCatalog {
            let target = CatalogTargetAddon(manifestUrl: option.manifestUrl, contentType: mediaType,
                catalogId: option.catalogId, genre: genre == "All genres" ? nil : genre,
                search: nil, supportsPagination: option.supportsPagination)
            guard !results.isEmpty else { return [] }
            return [.catalog(HomeCatalogSection(key: "browse-filtered-" + option.key,
                title: option.catalogName, subtitle: "", addonName: option.addonName,
                target: target, items: results, availableItemCount: Int32(results.count), hasMore: false))]
        }
        return sections.map { section in
            .catalog(HomeCatalogSection(key: section.key, title: section.title, subtitle: section.subtitle,
                addonName: section.addonName, target: section.target,
                items: section.items.filter { $0.type == mediaType },
                availableItemCount: section.availableItemCount, hasMore: section.hasMore))
        }
    }

    var body: some View {
        HomeView(model: model, browse: HomeBrowseConfiguration(
            rows: browseRows, items: results, filtered: filtered,
            selectionKey: [mediaType, catalog, genre, order].joined(separator: "|"),
            controls: AnyView(filters), emptyState: AnyView(emptyState),
            onItemFocus: { item in
                guard filtered, let item,
                      let index = discovery.discover?.items.firstIndex(where: { $0.id == item.id && $0.type == item.type }) else { return }
                discovery.discoverItemAppeared(at: index)
            }))
        .onAppear { discovery.start(); discovery.selectDiscoverType(mediaType) }
        .onDisappear { discovery.stop() }
        .onChange(of: discovery.discover?.selectedType) { _, selected in
            if let selected, selected != mediaType { discovery.selectDiscoverType(mediaType) }
        }
    }

    private var filters: some View {
        HStack(spacing: 24) {
            TVSelectionMenu(title: "Browse", value: mediaType == "movie" ? "Movies" : "Shows", options: ["Movies", "Shows"]) { mediaType = $0 == "Movies" ? "movie" : "series"; genre = "All genres"; catalog = "All catalogs"; discovery.selectDiscoverType(mediaType) }
            TVSelectionMenu(title: "Genre", value: genre, options: (discovery.discover?.selectedCatalog?.genreRequired == true ? [] : ["All genres"]) + availableGenres) { genre = $0; catalog = selectedCatalogLabel; discovery.selectDiscoverGenre($0 == "All genres" ? nil : $0) }
            TVSelectionMenu(title: "Catalog", value: catalog, options: ["All catalogs"] + (discovery.discover?.catalogOptions.map { $0.catalogName + " · " + $0.addonName } ?? [])) { selected in
                catalog = selected; genre = "All genres"
                if let option = discovery.discover?.catalogOptions.first(where: { $0.catalogName + " · " + $0.addonName == selected }) { discovery.selectDiscoverCatalog(option.key) }
            }
            TVSelectionMenu(title: "Sort", value: order, options: ["Recommended", "A–Z", "Highest rated"]) { order = $0; if filtered && catalog == "All catalogs" { catalog = selectedCatalogLabel } }
            if filtered { Button("Reset") { genre = "All genres"; catalog = "All catalogs"; order = "Recommended" }.buttonStyle(.glass) }
        }.padding(.bottom, 12)
    }

    @ViewBuilder private var emptyState: some View {
        if model.isLoading || discovery.discover?.isLoading == true {
            ProgressView("Loading titles…")
        } else if filtered {
            Text("No titles match these filters.").foregroundStyle(.secondary)
        } else {
            NavigationLink("Manage Add-ons") { AddonsView() }.buttonStyle(.glass)
        }
    }
}

/// Content differences only. Home owns the layout, scrim, pinned viewport, cards, and remote behavior.
struct HomeBrowseConfiguration {
    let rows: [HomeRow]
    let items: [MetaPreview]
    let filtered: Bool
    let selectionKey: String
    let controls: AnyView
    let emptyState: AnyView
    let onItemFocus: (MetaPreview?) -> Void
}
