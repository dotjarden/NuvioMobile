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

    static let `default` = PosterStyle()

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
        guard !landscapeCatalogRows, Self.landscapeSection(items: items) else { return self }
        var copy = self
        copy.landscapeCatalogRows = true
        return copy
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
