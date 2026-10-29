import SharedCore
import SwiftUI

// Search & Discover batch 2026-10-06 (O3 Stage Discover, plan A4): the Discover tab's root, what
// `MainTabView` mounts in `Tab("Discover", systemImage: "safari", value: 6)` when the placement is
// Own Tab (the default):
//
//     Tab("Discover", systemImage: "safari", value: 6) {
//         DiscoverTabRoot()
//             .tabBarImmersiveHide()
//             .railTabRoot(6)
//     }
//
// It owns the tab's view models (cached for the tab's life, across pushes and tab switches)
// and its own `NavigationStack(path:)` with the four destinations Search registers (`SearchView`),
// so a poster, a See All tile, the Grid pill, a person or a studio/network chip push inside the
// Discover tab. The watchers run while the tab is on screen: `start()` on appear, `stop()` on
// disappear (a stop keeps the rows; the next start resumes any fetch it cancelled).

// FEAT-73 (Steven rc4, D11): the tab lands on the grid-first page (`DiscoverGridPage`); its
// Browse pill pushes the per-genre stage rows (`DiscoverRowsPage`, host `.pushed`: it starts and
// stops its own model and pops on Menu at its top) inside this stack, opened on the grid's catalog.

/// See the file header.
struct DiscoverTabRoot: View {
    @StateObject private var model = DiscoverGridViewModel()
    /// The Browse page's rows, kept for the tab's life so a second Browse is instant.
    @StateObject private var rowsModel = DiscoverRowsViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            DiscoverGridPage(model: model, host: .tab, onBrowse: { catalogKey in
                rowsModel.show(catalogKey: catalogKey)
                path.append(DiscoverBrowseRoute(catalogKey: catalogKey))
            })
            .navigationDestination(for: DiscoverBrowseRoute.self) { _ in
                DiscoverRowsPage(model: rowsModel, host: .pushed, onOpenGrid: { route in
                    path.append(route)
                })
            }
            .navigationDestination(for: TitleRoute.self) { route in
                DetailView(preview: route.preview)
            }
            .navigationDestination(for: CatalogRoute.self) { route in
                CatalogGridView(route: route)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(personId: route.id, personName: route.name)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                EntityBrowseView(route: route)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
