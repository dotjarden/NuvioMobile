import SwiftUI
import SharedCore

/// Movie/show entry points share the existing catalog pipeline and detail/player routes.
/// Filtered catalogs use the shared paginated Discover pipeline while this tab is visible.
struct MediaBrowseView: View {
    @ObservedObject var model: HomeViewModel
    @State var mediaType: String
    @StateObject private var heroArt = HeroArtResolver()
    @StateObject private var heroTrailer = InlineTrailerCardModel()
    @FocusState private var heroFocused: Bool
    @FocusState private var focusedTitle: String?
    private var heroTarget: MetaPreview? { results.first(where: { $0.type + ":" + $0.id == focusedTitle }) ?? results.first }
    @StateObject private var discovery = SearchViewModel()
    @State private var genre = "All genres"
    @State private var catalog = "All catalogs"
    @State private var order = "Recommended"
    @Environment(\.posterStyle) private var posterStyle
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
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                GeometryReader { geometry in
                    if let presentation = heroArt.presented {
                        HomeHeroBackdrop(presentation: presentation, nuvioStyle: true, trailerModel: heroTrailer)
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.8)
                            .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.68), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    }
                }.ignoresSafeArea().allowsHitTesting(false)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        if sections.isEmpty && !model.isLoading {
                            ContentUnavailableView("No catalogs available", systemImage: "rectangle.stack", description: Text("Enable a catalog for this media type in Add-ons."))
                            NavigationLink("Manage Add-ons") { AddonsView() }.buttonStyle(.glass)
                        }
                        ZStack(alignment: .leading) {
                            if let presentation = heroArt.presented {
                                HomeHeroForeground(presentation: presentation, heroFocused: $heroFocused, compact: true, forceNuvioLayout: true)
                                    .padding(.horizontal, -Theme.Spacing.screen)
                            } else if model.isLoading || discovery.discover?.isLoading == true {
                                ProgressView("Loading titles…")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 440)
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
                        if filtered {
                            if discovery.discover?.isLoading == true { ProgressView("Loading titles…") }
                            if results.isEmpty && discovery.discover?.isLoading != true { Text("No titles match these filters.").foregroundStyle(.secondary) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: posterStyle.width + Theme.Spacing.rowGap), spacing: Theme.Spacing.rowGap)], spacing: 40) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink(value: TitleRoute(preview: item)) { PosterCard(title: item.name, imageURL: item.poster) }.cardFocusButtonStyle().posterButtonShape().focused($focusedTitle, equals: item.type + ":" + item.id).onAppear { discovery.discoverItemAppeared(at: index) }
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
                                                .cardFocusButtonStyle().posterButtonShape().focused($focusedTitle, equals: item.type + ":" + item.id)
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
        }
        .task(id: heroTarget.map { $0.type + ":" + $0.id }) { heroArt.present(heroTarget, isFolder: false) }
        .onAppear { model.acquire(); discovery.start(); discovery.selectDiscoverType(mediaType) }
        .onDisappear { model.release(); discovery.stop() }
        .onChange(of: discovery.discover?.selectedType) { _, selected in
            if let selected, selected != mediaType { discovery.selectDiscoverType(mediaType) }
        }
    }
}
