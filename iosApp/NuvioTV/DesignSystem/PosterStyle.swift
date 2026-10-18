import Combine
import SwiftUI
import SharedCore

/// Resolved poster-card styling for the tvOS UI, derived from the shared `PosterCardStyleRepository`
/// (which stores phone-scale dp and syncs across devices). Widths are scaled to tvOS points so the
/// same synced setting looks right on both platforms; corner radius is used directly as points
/// (default 12 == the previous fixed look).
struct PosterStyle: Equatable {
    var width: CGFloat = Theme.Size.posterWidth
    var height: CGFloat = Theme.Size.posterHeight
    var cornerRadius: CGFloat = Theme.Radius.card
    var showTitle: Bool = true
    var landscapeCatalogRows: Bool = false
    /// BUG-162 (Steven, rc4 verdict 2026-10-16: his add-on's landscape cards "much too small", the
    /// row heading ~120 pt above them at Medium+): true only when `resolved(forSectionItems:)`
    /// turned this row landscape from its items' `posterShape` (BUG-157). Such a row is planned at
    /// the portrait height (the slot is `expandedCardHeight`, the poster height), its cards REST at
    /// the landscape folder-tile size (`cardWidth` / `cardHeight`, D16) and GROW to the trailer
    /// tile (`expandedCardWidth` / `expandedCardHeight`). The GLOBAL Landscape Posters toggle
    /// (`landscapeCatalogRows` without this) keeps 360×203 in both states.
    var landscapeFromShape: Bool = false

    static let `default` = PosterStyle()

    /// BUG-162: the RESTING card size of a row drawn with this style. Portrait: the poster.
    /// Global Landscape Posters: the fixed 360×203 landscape card. Shape landscape (BUG-157 per-row):
    /// D16 (Steven, rc5 verdict 2026-10-17: the 624×351 cards were "much too large", he wants them
    /// "the same size as the collection posters normally, and only enlarge them when the trailer
    /// starts"): the landscape folder tile's rule (`FolderTile`, CollectionsUI.swift), `width × 16/9`
    /// wide × `width` tall, 416×234 at Medium+. The card grows to `expandedCardWidth` ×
    /// `expandedCardHeight` at the inline trailer's `.wide` stage (`InlineTrailerCard.artworkWidth`).
    var cardWidth: CGFloat {
        guard landscapeCatalogRows else { return width }
        return landscapeFromShape ? width * (16.0 / 9.0) : Theme.Size.landscapeWidth
    }

    /// BUG-162 / D16: see `cardWidth`.
    var cardHeight: CGFloat {
        guard landscapeCatalogRows else { return height }
        return landscapeFromShape ? width : Theme.Size.landscapeHeight
    }

    /// BUG-162 / D16: the card's size once its inline trailer reaches the `.wide` stage. Portrait and
    /// shape-landscape rows: the 16:9 trailer tile at the poster's height (UX-4a; 624×351 at
    /// Medium+). Global Landscape Posters: the card itself (rest == expanded, the tile is a pure
    /// dissolve there). The height is also the row's artwork SLOT: a shape row's resting card sits at
    /// the top of a poster-height slot and grows down into it, so the heading never moves.
    var expandedCardWidth: CGFloat {
        landscapeRowGeometry ? Theme.Size.landscapeWidth : height * (16.0 / 9.0)
    }

    /// BUG-162 / D16: see `expandedCardWidth`.
    var expandedCardHeight: CGFloat {
        landscapeRowGeometry ? Theme.Size.landscapeHeight : height
    }

    /// BUG-162 / D16: the card's artwork size at a morph stage (`expanded` = the inline trailer's
    /// `.wide` stage, `InlineTrailerModel.layoutExpanded`). One rule for every row kind: portrait
    /// grows width only (UX-4a), a shape-landscape card grows both ways (D16), the global toggle's
    /// card never changes. `.reveal` dissolves at the rest size (rc1 R2: never grow while
    /// translucent), so only `.wide` reads `true`.
    func artworkSize(expanded: Bool) -> CGSize {
        expanded
            ? CGSize(width: trailerCardWidth, height: trailerCardHeight)
            : CGSize(width: cardWidth, height: cardHeight)
    }

    /// Steven (rc6 follow-up 2026-10-18 19:47Z, reversing D16's grow): a shape-landscape card plays
    /// its trailer AT ITS RESTING SIZE: the focus lift already enlarges the focused card, and a card
    /// that grows shifts its row and the heading under it. Portrait rows still morph to the 16:9 tile
    /// (UX-4a); the global Landscape Posters card never changed. `expandedCardWidth/Height` stay the
    /// row's artwork SLOT for Classic's planners; this is only what the card grows TO.
    var trailerCardWidth: CGFloat { landscapeFromShape ? cardWidth : expandedCardWidth }

    /// See `trailerCardWidth`.
    var trailerCardHeight: CGFloat { landscapeFromShape ? cardHeight : expandedCardHeight }

    /// BUG-162: the row is a fixed-size landscape row (the global toggle), shorter than a portrait
    /// row. False for portrait rows and for shape-landscape rows, which keep the portrait height:
    /// the strip and the pinned-row planners read this, not `landscapeCatalogRows`.
    var landscapeRowGeometry: Bool { landscapeCatalogRows && !landscapeFromShape }

    /// tvOS points per stored dp (default width dp 126 → 220 pt).
    private static let dpToPoint = Theme.Size.posterWidth / 126.0

    init() {}

    init(from state: PosterCardStyleUiState) {
        let scaledWidth = CGFloat(state.widthDp) * PosterStyle.dpToPoint
        width = scaledWidth
        height = scaledWidth * 1.5 // 2:3 portrait — matches shared heightDp = widthDp * 3 / 2
        cornerRadius = CGFloat(state.cornerRadiusDp)
        showTitle = !state.hideLabelsEnabled
        landscapeCatalogRows = state.catalogLandscapeModeEnabled
        #if DEBUG
        // Home Stage & Strip (P1 §8, #11): Poster Size and Hide Titles are synced settings with no
        // UserDefaults key, so the FA87 fixture (Medium) needs launch overrides for Gate 1, testS13
        // and test47/48. App-wide, DEBUG only.
        if let dp = PosterStyleDebugOverride.widthDp {
            width = dp * PosterStyle.dpToPoint
            height = width * 1.5
        }
        if let hide = PosterStyleDebugOverride.hideTitles {
            showTitle = !hide
        }
        #endif
    }

    /// Home Stage & Strip (P1 §2, #23): this style laid out at poster height `newHeight`, width
    /// following at 2:3. A re-layout, not a `scaleEffect`: the strip hands it to its rows when a
    /// synced custom Poster Size is too tall for the stage to keep its 420 pt floor, and every row
    /// reads `\.posterStyle`, so nothing overflows onto the next heading.
    func withHeight(_ newHeight: CGFloat) -> PosterStyle {
        var copy = self
        copy.height = newHeight
        copy.width = newHeight / 1.5
        return copy
    }
}

// MARK: - Per-row landscape shape (BUG-157)

extension PosterStyle {
    /// BUG-157 (Steven, beta.19-rc3 follow-up 2026-10-14): whether a catalog row whose items carry
    /// these shapes draws landscape (16:9) cards. True when STRICTLY more than half of the items are
    /// landscape: an add-on that tags its catalog tags every item, and one stray tag (or a TMDB
    /// enrichment that dropped it) never flips a whole row. A tie, an empty row and `square` (tvOS
    /// has no square card; it reads as a poster) stay portrait. Upstream decides per CARD
    /// (`HomePosterCard`); tvOS keeps one shape per row so the row's height, the pinned title and
    /// the inline trailer morph stay one geometry.
    nonisolated static func landscapeSection<S: Sequence>(_ isLandscape: S) -> Bool where S.Element == Bool {
        var landscape = 0
        var total = 0
        for flag in isLandscape {
            total += 1
            if flag { landscape += 1 }
        }
        return total > 0 && landscape * 2 > total
    }

    /// `landscapeSection` over a row's items (`MetaPreview.posterShape`, from the add-on's
    /// `posterShape` field).
    static func landscapeSection(items: [MetaPreview]) -> Bool {
        landscapeSection(items.lazy.map { $0.posterShape == PosterShape.landscape })
    }

    /// BUG-157: this style for a row of `items`: `landscapeCatalogRows` turns on when the row is a
    /// landscape-shape catalog, and is left as it is otherwise (the global toggle wins either way).
    func resolved(forSectionItems items: [MetaPreview]) -> PosterStyle {
        guard !landscapeCatalogRows, Self.landscapeSectionCached(items: items) else { return self }
        var copy = self
        copy.landscapeCatalogRows = true
        copy.landscapeFromShape = true  // BUG-162: sized off the poster height, see `cardWidth`
        return copy
    }

    /// Review r1 (P3-11): `CatalogRowView` reads its resolved style many times per body and per card
    /// hop, and every read bridged up to 100 `posterShape` reads into Kotlin. A row's items are an
    /// immutable snapshot, so the answer is memoised on (count, first id, last id) — two bridge
    /// reads — in a small main-thread table that is cleared when it grows past 512 rows.
    @MainActor private static var landscapeByRow: [String: Bool] = [:]

    @MainActor
    static func landscapeSectionCached(items: [MetaPreview]) -> Bool {
        guard let first = items.first, let last = items.last else { return false }
        let key = "\(items.count)|\(first.id)|\(last.id)"
        if let hit = landscapeByRow[key] { return hit }
        if landscapeByRow.count > 512 { landscapeByRow.removeAll(keepingCapacity: true) }
        let value = landscapeSection(items: items)
        landscapeByRow[key] = value
        return value
    }
}

#if DEBUG
/// Home Stage & Strip (P1 §8, #11): DEBUG-only launch overrides read by `PosterStyle.init(from:)`.
///
///     -debug.posterSizeOverride small|medium|mediumPlus|large   (105 / 126 / 134 / 154 dp)
///     -debug.posterHideTitles YES|NO
///
/// Launch-latched (read once). No Zoom needs no knob: `-no_zoom_on_focus YES` already lands in the
/// `@AppStorage` key.
nonisolated enum PosterStyleDebugOverride {
    static let widthDp: CGFloat? = {
        switch UserDefaults.standard.string(forKey: "debug.posterSizeOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "small": return 105
        case "medium": return 126
        case "mediumplus", "medium+", "medium_plus": return 134
        case "large": return 154
        default: return nil
        }
    }()

    static let hideTitles: Bool? = {
        guard UserDefaults.standard.object(forKey: "debug.posterHideTitles") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.posterHideTitles")
    }()
}
#endif

private struct PosterStyleKey: EnvironmentKey {
    static let defaultValue = PosterStyle.default
}

extension EnvironmentValues {
    var posterStyle: PosterStyle {
        get { self[PosterStyleKey.self] }
        set { self[PosterStyleKey.self] = newValue }
    }
}

/// Observes the shared `PosterCardStyleRepository` and republishes a resolved `PosterStyle` for the
/// environment. Owned at the app root and injected via `.environment(\.posterStyle,)`; profile-scoped
/// (the repo reloads on profile switch through the lifecycle coordinator).
@MainActor
final class PosterStyleModel: ObservableObject {
    @Published private(set) var style = PosterStyle.default

    private var watcher: FlowWatcher?

    func start() {
        guard watcher == nil else { return }
        PosterCardStyleRepository.shared.ensureLoaded()
        watcher = FlowWatcherKt.watch(PosterCardStyleRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? PosterCardStyleUiState else { return }
            self.style = PosterStyle(from: state)
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
    }

    deinit { watcher?.cancel() }
}
