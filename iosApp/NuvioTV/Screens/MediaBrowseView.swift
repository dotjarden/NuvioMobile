import SwiftUI
import SharedCore

/// Movie/show entry points share the existing catalog pipeline and detail/player routes.
/// They never start a competing SearchRepository or replace account-specific catalogs.
struct MediaBrowseView: View {
    @ObservedObject var model: HomeViewModel
    let mediaType: String
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
                    }.padding(Theme.Spacing.screen)
                }.scrollClipDisabled().reportsScrollToTabBar(tab: mediaType == "movie" ? "Movies" : "Shows").sidebarMenuReveal()
            }
            .navigationDestination(for: TitleRoute.self) { DetailView(preview: $0.preview) }
            .navigationDestination(for: CatalogRoute.self) { CatalogGridView(route: $0) }
            .navigationDestination(for: PersonRoute.self) { PersonDetailView(personId: $0.id, personName: $0.name) }
            .navigationDestination(for: EntityRoute.self) { EntityBrowseView(route: $0) }
        }.onAppear { model.acquire() }.onDisappear { model.release() }
    }
}
