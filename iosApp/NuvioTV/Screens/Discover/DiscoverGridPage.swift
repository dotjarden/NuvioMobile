import SharedCore
import SwiftUI

// FEAT-73 (Steven rc4, decision D11): the grid-first Discover page, what the viewer lands on from
// the Discover tab (Own Tab) and from Search's Movies / Series tiles (Under Search).
//
//     DiscoverGridPage                 ZStack(.topLeading)
//     ├─ Theme background
//     ├─ ScrollView(.vertical)         one vertical scroll, Library's pattern
//     │  └─ VStack
//     │     ├─ band  .focusSection()   [Type ▾] [Genre ▾] [Catalog ▾] [⊞ Browse]
//     │     │                          discover.typePicker / .genrePicker / .catalogPicker /
//     │     │                          .browseButton. Tabs mode: below the system tab bar
//     │     │                          (`DiscoverPillBandGeometry.tabsTop`); Rail: `railTop`.
//     │     └─ grid  .focusSection()   LazyVGrid, the `CatalogGridView` cell recipe, `.id(gridKey)`
//     │                                (a Type / Genre / Catalog pick starts it at the top while the
//     │                                pill keeps focus), next page within 8 of the end
//     └─ DEBUG probe leaf `discover_grid_state mode=grid type= catalog= genre= items= state=`
//
// Browse pushes the per-genre stage rows (`DiscoverRowsPage`, host `.pushed`) on the grid's
// catalog. The Genre pill shows "All" + the genres when the genre is optional, only the genres
// when it is required, and is hidden when the catalog has none. Catalog sits last: the secondary
// pick (Type and Genre are what the viewer changes most).
//
// Remote: Down from a pill → the grid; Up from the grid's first line → the band; Menu → the tab
// host reveals the rail (`.railMenuReveal()`, Library's rule) or is the system default in Tabs
// mode; pushed (Under Search), the system pops. `.railReturnRoute` "discover" puts focus back on
// the tile it left, else the default (the band).

/// Search's navigation value for the pushed grid-first Discover page (Under Search placement), and
/// the tab root's push target for Browse. `DiscoverRoute` (the page) lives in `DiscoverRowsPage.swift`.
struct DiscoverBrowseRoute: Hashable {
    /// The grid's catalog, which the rows open on.
    let catalogKey: String
}

/// See the file header.
struct DiscoverGridPage: View {
    @ObservedObject var model: DiscoverGridViewModel
    let host: DiscoverHost
    /// Pushed: the entry tile's type (`DiscoverRoute.type`), selected once after the options arrive.
    let routeType: String?
    /// The Browse pill: the host shows these rows on `catalogKey` and pushes them.
    let onBrowse: (String) -> Void

    @State private var box = DiscoverGridPageBox()
    @State private var scrolledDown = false
    @FocusState private var focusedTile: String?

    @Environment(\.posterStyle) private var posterStyle
    @Environment(\.dismiss) private var dismiss
    /// Held, never observed: written on a scroll crossing only.
    @Environment(\.navigationChrome) private var navigationChrome

    init(model: DiscoverGridViewModel,
         host: DiscoverHost,
         routeType: String? = nil,
         onBrowse: @escaping (String) -> Void) {
        self.model = model
        self.host = host
        self.routeType = routeType
        self.onBrowse = onBrowse
    }

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: posterStyle.width + Theme.Spacing.rowGap),
            spacing: Theme.Spacing.rowGap
        )]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Palette.background.ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if model.selectedType != nil {
                        band
                    }
                    content
                }
                .padding(.top, DiscoverPillBandGeometry.top(isRail: NavigationChrome.isRail()))
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.screen)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .modifier(DiscoverGridScrollReport(enabled: host == .tab, scrolledDown: $scrolledDown))

            #if DEBUG
            DiscoverGridProbeLabel(type: model.selectedType ?? "-",
                                   catalog: model.selectedCatalogKey ?? "-",
                                   // Spaces would split the token ("Science Fiction").
                                   genre: (model.selectedGenre ?? "-").replacingOccurrences(of: " ", with: "_"),
                                   items: model.items.count,
                                   state: stateToken)
            #endif
        }
        .modifier(DiscoverGridMenuRevealModifier(enabled: host == .tab))
        .railReturnRoute { gridRailRoute }
        .onAppear {
            // The tab root starts its own model (on the stack, so a push keeps it running); the
            // pushed page's model belongs to Search's owner.
            if host == .pushed { model.start() }
            applyRouteType()
        }
        .onDisappear {
            if host == .pushed { model.stop() }
        }
        .onChange(of: model.typeOptions) { _, _ in
            applyRouteType()
        }
        // Rail Hide While Browsing (H9): the Own tab's rail follows the grid's scroll, like Home's.
        .onChange(of: scrolledDown) { _, down in
            guard host == .tab, NavigationChrome.isRail() else { return }
            navigationChrome.setScrolledDown(tab: DiscoverHost.tabValue, down)
        }
    }

    // MARK: Band

    private var band: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                if let type = model.selectedType {
                    PillMenu(title: DiscoverRowsPlan.typeLabel(type),
                             systemImage: "film.stack",
                             selection: Binding(get: { type }, set: { model.select(type: $0) }),
                             options: model.typeOptions,
                             id: "discover.typePicker",
                             pickerTitle: String(localized: "Type"),
                             label: { DiscoverRowsPlan.typeLabel($0) })
                }
                if let option = model.selectedOption, let genres = DiscoverGridPlan.genreChoices(option) {
                    let current = DiscoverGridPlan.pillValue(model.selectedGenre)
                    PillMenu(title: DiscoverGridPlan.genreLabel(current),
                             systemImage: "theatermasks",
                             selection: Binding(get: { current }, set: { model.select(genrePill: $0) }),
                             options: genres,
                             id: "discover.genrePicker",
                             pickerTitle: String(localized: "Genre"),
                             label: { DiscoverGridPlan.genreLabel($0) })
                }
                if let type = model.selectedType, let selected = model.selectedOption {
                    let catalogs = model.catalogOptions(for: type)
                    if catalogs.count > 1 {
                        PillMenu(title: DiscoverRowsPlan.catalogLabel(selected, among: catalogs),
                                 systemImage: "square.stack",
                                 selection: Binding(get: { selected.key }, set: { model.select(catalogKey: $0) }),
                                 options: catalogs.map(\.key),
                                 id: "discover.catalogPicker",
                                 pickerTitle: String(localized: "Catalog"),
                                 label: { key in
                                     catalogs.first { $0.key == key }
                                         .map { DiscoverRowsPlan.catalogLabel($0, among: catalogs) } ?? key
                                 })
                    }
                }
                if let key = model.selectedCatalogKey {
                    PillButton(title: String(localized: "Browse"),
                               systemImage: "rectangle.grid.1x2",
                               id: "discover.browseButton") {
                        onBrowse(key)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        // The stock Menu buttons lift on focus; don't crop the lift.
        .scrollClipDisabled()
        // Full width, so Up from any grid column finds the band (the focus engine searches straight up).
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.selectedType == nil {
            sourcesPanel
        } else {
            switch model.phase {
            case .loading:
                loadingPanel
            case .failed:
                failedPanel
            case .empty:
                if model.isLoadingMore { loadingPanel } else { emptyPanel }
            case .loaded:
                grid
            }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    let key = Self.tileKey(item)
                    NavigationLink(value: TitleRoute(preview: item)) {
                        PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.rawPosterUrl)
                    }
                    .cardFocusButtonStyle()
                    .posterButtonShape()
                    .titleHoldMenu(preview: item)
                    .focused($focusedTile, equals: key)
                    .accessibilityIdentifier(index == 0 ? "discover.gridFirstTile" : "discover.gridTile")
                    .onAppear { model.itemAppeared(at: index) }
                }
            }
            if model.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
            }
        }
        // A pick starts the grid at its top (focus stays on the pill that made it).
        .id(model.gridKey)
        .focusSection()
    }

    static func tileKey(_ item: MetaPreview) -> String { "\(item.type):\(item.id)" }

    private var loadingPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Loading\u{2026}")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            // BUG-47: a pushed page with nothing focusable strands focus on the tab bar, where
            // Menu exits the app. The band is focusable once a selection exists; before it, this.
            if host == .pushed, model.selectedType == nil {
                goBack
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    /// Settled with nothing to show. The band stays the focus anchor; pushed, Go Back too (BUG-47).
    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Nothing here yet.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            if host == .pushed { goBack }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var failedPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Couldn't load Discover.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.md) {
                Button("Try Again") { model.retry() }
                    .buttonStyle(.bordered)
                if host == .pushed { goBack }
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    /// No selection: `DiscoverRowsPage`'s copy for each reason.
    @ViewBuilder
    private var sourcesPanel: some View {
        switch model.sourcesState {
        case .waiting, .ready:
            loadingPanel
        case .noAddons:
            sourcesMessage(String(localized: "Install and enable an add-on to browse its catalogs."))
        case .noCatalogs:
            sourcesMessage(String(localized: "Your add-ons don't expose browsable catalogs."))
        case .manifestFailure(let message):
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Couldn't load your add-ons.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.accent)
                Text(message)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        model.retry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(Theme.Font.meta)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                    .buttonStyle(.chip)
                    if host == .pushed { goBack }
                }
            }
            .padding(.top, Theme.Spacing.lg)
        }
    }

    private func sourcesMessage(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            if host == .pushed { goBack }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var goBack: some View {
        Button("Go Back") { dismiss() }
            .buttonStyle(.bordered)
    }

    private var stateToken: String {
        model.selectedType == nil ? model.sourcesState.token : model.phase.token
    }

    // MARK: Route type, rail

    /// Pushed: the entry tile's type, applied once, as soon as the type options name it (a first
    /// push can land before the watcher's first value). `DiscoverRowsPage.applyRouteType`'s rule.
    private func applyRouteType() {
        guard host == .pushed, let type = routeType, !box.routeTypeApplied else { return }
        let types = model.typeOptions
        guard !types.isEmpty else { return }
        box.routeTypeApplied = true
        guard types.contains(type), model.selectedType != type else { return }
        model.select(type: type)
    }

    /// Where a rail exit puts focus back: the tile focus left from (when it is still in the grid),
    /// else the default hand-off (the band).
    private var gridRailRoute: RailReturnRoute {
        let pageBox = box
        let gridModel = model
        let focus = $focusedTile
        return RailReturnRoute(
            name: "discover",
            capture: {
                pageBox.railSavedTile = focus.wrappedValue
            },
            restore: {
                let saved = pageBox.railSavedTile
                pageBox.railSavedTile = nil
                guard let saved,
                      gridModel.items.contains(where: { DiscoverGridPage.tileKey($0) == saved }) else { return false }
                focus.wrappedValue = saved
                return true
            },
            vetoesLeftArm: { false }
        )
    }
}

/// The page's bookkeeping, in a reference box so it writes no view state.
@MainActor
final class DiscoverGridPageBox {
    /// Pushed: the route's type has been looked at (applied or found absent).
    var routeTypeApplied = false
    /// The tile the rail route returns to (captured when the rail arms; nil = default focus).
    var railSavedTile: String?
}

/// `.railMenuReveal()` for the tab host only (a pushed page pops on Menu, the system default).
private struct DiscoverGridMenuRevealModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.railMenuReveal()
        } else {
            content
        }
    }
}

/// The tab host's scroll drives the floating tab bar's auto-hide (Library's `reportsScrollToTabBar`)
/// and, through `scrolledDown`, the rail's Hide While Browsing. Pushed, nothing (Search's own rule).
private struct DiscoverGridScrollReport: ViewModifier {
    let enabled: Bool
    @Binding var scrolledDown: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.reportsScrollToTabBar(tab: "Discover", isScrolledDown: $scrolledDown)
        } else {
            content
        }
    }
}

// MARK: - DEBUG readout

#if DEBUG
/// `discover_grid_state mode=grid type=<type|-> catalog=<catalog key|-> genre=<genre|-> items=<n>
/// state=<loading|loaded|empty|failed|waiting|noaddons|nocatalogs|manifestfailure>`. A leaf.
private struct DiscoverGridProbeLabel: View {
    let type: String
    let catalog: String
    let genre: String
    let items: Int
    let state: String

    var body: some View {
        Text(verbatim: "discover_grid_state mode=grid type=\(type) catalog=\(catalog) genre=\(genre) items=\(items) state=\(state)")
            .font(.system(size: 8))
            .opacity(0.011)
            .accessibilityIdentifier("discover_grid_state")
            .allowsHitTesting(false)
    }
}
#endif
