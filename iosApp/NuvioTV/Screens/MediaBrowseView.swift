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
    @Environment(\.posterStyle) private var posterStyle
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
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        if model.isLoading && sections.isEmpty { ProgressView("Loading catalogs…") }
                        if sections.isEmpty && !model.isLoading {
                            ContentUnavailableView("No catalogs available", systemImage: "rectangle.stack", description: Text("Enable a catalog for this media type in Add-ons."))
                            NavigationLink("Manage Add-ons") { AddonsView() }.buttonStyle(.glass)
                        }
                        HStack(spacing: 24) {
                            TVSelectionMenu(title: "Browse", value: mediaType == "movie" ? "Movies" : "Shows", options: ["Movies", "Shows"]) { mediaType = $0 == "Movies" ? "movie" : "series"; genre = "All genres"; catalog = "All catalogs"; discovery.selectDiscoverType(mediaType) }
                            TVSelectionMenu(title: "Genre", value: genre, options: (discovery.discover?.selectedCatalog?.genreRequired == true ? [] : ["All genres"]) + availableGenres) { genre = $0; catalog = discovery.discover?.selectedCatalog?.catalogName ?? "Catalog"; discovery.selectDiscoverGenre($0 == "All genres" ? nil : $0) }
                            TVSelectionMenu(title: "Catalog", value: catalog, options: ["All catalogs"] + (discovery.discover?.catalogOptions.map { $0.catalogName + " · " + $0.addonName } ?? [])) { selected in
                                catalog = selected; genre = "All genres"
                                if let option = discovery.discover?.catalogOptions.first(where: { $0.catalogName + " · " + $0.addonName == selected }) { discovery.selectDiscoverCatalog(option.key) }
                            }
                            TVSelectionMenu(title: "Sort", value: order, options: ["Recommended", "A–Z", "Highest rated"]) { order = $0; if filtered && catalog == "All catalogs" { catalog = discovery.discover?.selectedCatalog?.catalogName ?? "Catalog" } }
                            if filtered { Button("Reset") { genre = "All genres"; catalog = "All catalogs"; order = "Recommended" }.buttonStyle(.glass) }
                        }.padding(.bottom, 12)
                        if !filtered, let item = results.first { featured(item) }
                        if filtered {
                            if discovery.discover?.isLoading == true { ProgressView("Loading titles…") }
                            if results.isEmpty && discovery.discover?.isLoading != true { Text("No titles match these filters.").foregroundStyle(.secondary) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: posterStyle.width + Theme.Spacing.rowGap), spacing: Theme.Spacing.rowGap)], spacing: 40) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink(value: TitleRoute(preview: item)) { PosterCard(title: item.name, imageURL: item.poster) }.cardFocusButtonStyle().posterButtonShape().onAppear { discovery.discoverItemAppeared(at: index) }
                                }
                            }
                        } else {
                        ForEach(sections, id: \.key) { section in
                            VStack(alignment: .leading, spacing: 20) {
                                HStack {
                                    Text(section.title).font(Theme.Font.sectionTitle)
                                    Spacer()
                                    NavigationLink(value: CatalogRoute(section: section)) { Label("See all", systemImage: "chevron.right") }.buttonStyle(.glass)
                                }
                                ScrollView(.horizontal) {
                                    LazyHStack(spacing: Theme.Spacing.rowGap) {
                                        ForEach(section.items.filter { $0.type == mediaType }, id: \.id) { item in
                                            NavigationLink(value: TitleRoute(preview: item)) { PosterCard(title: item.name, imageURL: item.poster) }
                                                .cardFocusButtonStyle().posterButtonShape()
                                        }
                                    }.padding(.vertical, 20)
                                }.scrollClipDisabled()
                            }
                        }
                        }
                    }.padding(Theme.Spacing.screen)
                }.scrollClipDisabled().reportsScrollToTabBar(tab: "Browse").sidebarMenuReveal()
            }
            .navigationDestination(for: TitleRoute.self) { DetailView(preview: $0.preview) }
            .navigationDestination(for: CatalogRoute.self) { CatalogGridView(route: $0) }
            .navigationDestination(for: PersonRoute.self) { PersonDetailView(personId: $0.id, personName: $0.name) }
            .navigationDestination(for: EntityRoute.self) { EntityBrowseView(route: $0) }
        }.onAppear { model.acquire(); discovery.start(); discovery.selectDiscoverType(mediaType) }
        .onDisappear { model.release(); discovery.stop() }
        .onChange(of: discovery.discover?.selectedType) { _, selected in
            if let selected, selected != mediaType { discovery.selectDiscoverType(mediaType) }
        }
    }
    private func featured(_ item: MetaPreview) -> some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                AsyncImage(url: URL(string: item.banner ?? item.poster ?? "")) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: proxy.size.width, height: 450).clipped()
            }
            LinearGradient(colors: [Theme.Palette.background, Theme.Palette.background.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 22) {
                Text(item.name).font(.system(size: 54, weight: .bold)).lineLimit(2)
                Text(item.genres.prefix(3).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                Text(item.description_ ?? "").font(.body).lineLimit(3)
                NavigationLink(value: TitleRoute(preview: item)) { Label("View details", systemImage: "info.circle") }.buttonStyle(.glass)
            }.frame(maxWidth: 720, alignment: .leading).padding(36)
        }.frame(height: 450).clipShape(RoundedRectangle(cornerRadius: 24)).padding(.bottom, 16)
    }

}
