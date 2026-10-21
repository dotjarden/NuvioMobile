import SharedCore
import SwiftUI

/// Home Stage & Strip (P1 E6): the row-to-hero adapters and per-row artwork warm-ups, moved out of
/// `HomeView` verbatim so the Stage controller (`StageController.report`/`rowAppeared`) and the
/// folder Rows page (P2, S6) run exactly what Classic runs. `HomeView`'s private functions are
/// one-line forwards to these, so Classic is unchanged.
enum HomeRowPreviews {

    /// BUG-38 round three: adapts a collection folder to the hero's `MetaPreview` shape so a
    /// focused folder tile can drive the hero with the folder's OWN artwork — `banner` is the
    /// configured `heroBackdropUrl`, `logo` the `titleLogoUrl` (both read by the existing
    /// `heroBackdropURL(for:)` / `heroLogoURL(for:)` chains with no special casing), and `poster`
    /// the cover (the backdrop chain's last fallback). `type` is the `collectionHeroType`
    /// sentinel the trailer, enrichment and CTA gates key on. `releaseInfo` carries the parent
    /// collection's title (read by `HeroLogo`'s text fallback and kept for rc14's BUG-119 history;
    /// since W3-14 / BUG-211 both hero forms draw the merged logo box, which ignores it) and
    /// `description` the folder's line for that box; H-2's "no caption under the wordmark"
    /// (2026-08-22) holds unless Show Catalog Details is on. `genres` is empty for a folder
    /// preview. Nil when the folder carries neither a backdrop nor a logo — such a folder has
    /// nothing of its own to show, so focusing it leaves the hero alone rather than painting a
    /// poster-shaped cover across the backdrop.
    ///
    /// B1 (BUG-145 + BUG-159 + FEAT-67, Steven's rc4 no-go on "Aventure · 8 sources"): the
    /// `description` line rides `showsDetails` (Show Catalog Details in Headings,
    /// `HeadingDetailsSetting`, default off). Off, it is nil: the hero-ON folder box keeps the
    /// full-height wordmark and the hero-OFF panel's synopsis slot stays empty; the meta line
    /// (`releaseInfo`, the collection title) is unchanged either way.
    static func folder(collection: NuvioCollection, folder: CollectionFolder, showsDetails: Bool) -> MetaPreview? {
        let backdrop = folder.heroBackdropUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let logo = folder.titleLogoUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(backdrop?.isEmpty ?? true) || !(logo?.isEmpty ?? true) else { return nil }
        return MetaPreview(
            id: "\(collectionHeroIdScheme)\(collection.id)/\(folder.id)",
            type: collectionHeroType,
            name: folder.title.trimmingCharacters(in: .whitespacesAndNewlines),
            // Wave H (BUG-86b): the cover is NOT a hero fallback. It is the tile's own square
            // artwork, so it is always already cached — which meant the hero painted it instantly,
            // scaled-to-fill into a 16:9 frame, and then swapped it for the real backdrop: the
            // "flat colour block, then the mosaic pops in larger and shrinks into place" the tester
            // filmed. With no fallback the previous hero simply stays up until the folder's own
            // backdrop resolves (`HeroArtResolver.folderDeadline`), and the row's `.onAppear`
            // prefetch means it usually already has.
            poster: nil,
            banner: (backdrop?.isEmpty ?? true) ? nil : backdrop,
            logo: (logo?.isEmpty ?? true) ? nil : logo,
            posterShape: .poster,
            // rc14 (BUG-119): the PANEL form once drew a folder hero through the three-slot
            // column (`HomeHeroForeground.nuvioLayout`), which needed this text. W3-14 / BUG-211
            // (rc11 verdict, 2026-10-21): the panel draws the merged logo box again, so the
            // collection title is only `HeroLogo`'s text fallback now. B1 (rc4 verdict,
            // 2026-10-16): the source-count line is behind `showsDetails`.
            description: showsDetails ? HomeView.folderHeroDescription(collection: collection, folder: folder) : nil,
            releaseInfo: collection.title.trimmingCharacters(in: .whitespacesAndNewlines),
            rawReleaseDate: nil,
            popularity: nil,
            voteCount: nil,
            imdbRating: nil,
            genres: [],
            rawPosterUrl: nil,
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: false
        )
    }

    /// UX-7: adapts a Continue Watching entry to the hero's `MetaPreview` shape so a focused CW
    /// card can drive the hero the same way a catalog poster does. Kotlin default args aren't
    /// exported to Swift, so every `MetaPreview` field has to be supplied explicitly — the fields
    /// CW doesn't carry (rating, popularity, etc.) go in as nil/empty rather than guessed.
    nonisolated static func entry(_ entry: WatchProgressEntry) -> MetaPreview {
        Self.entry(entry, logo: nil)
    }

    /// `entry(_:)` with a logo. Classic passes none (its hero resolves the logo itself); the Stage
    /// copy passes the entry's own `logo` (`StageCopy.preview(from:)`).
    nonisolated static func entry(_ entry: WatchProgressEntry, logo: String?) -> MetaPreview {
        MetaPreview(
            id: entry.parentMetaId,
            type: entry.parentMetaType,
            name: entry.title,
            poster: entry.poster,
            banner: entry.background,
            logo: logo,
            posterShape: .poster,
            description: nil,
            releaseInfo: nil,
            rawReleaseDate: nil,
            popularity: nil,
            voteCount: nil,
            imdbRating: nil,
            genres: [],
            rawPosterUrl: nil,
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: false
        )
    }

    /// Wave H: every folder's hero backdrop AND title logo in one collection row. A folder hero has
    /// no poster fallback, so these two URLs are the whole of what its hero can ever paint.
    static func collectionArtURLs(_ collection: NuvioCollection) -> [String] {
        collection.folders.flatMap { folder -> [String] in
            [folder.heroBackdropUrl, folder.titleLogoUrl]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    /// The warm-up half of Home's per-row focus report (UX-7 / FEAT-42): on a row's first non-nil
    /// report, prefetch its first backdrops (the same `heroBackdropURL` chain the hero renders)
    /// and batch a `TitleLogoStore` lookup for the row's own logo candidates. `done` is the
    /// caller's per-row dedup set (keyed by report source), so each row pays once per lifetime.
    ///
    /// `logoCandidates` is the row's leading items (only catalog rows pass a non-empty closure).
    /// BUG-151 (Steven rc3/rc4): the same items also warm `StageLocalizedCopyStore`, so a title
    /// focused later in the row commits with its localized name, synopsis and genres. For that the
    /// Stage strip and the folder Rows page now pass the row's leading items UNFILTERED, and the
    /// logo half re-applies `TitleLogoStore.isLookupCandidate` here (idempotent, so Classic's
    /// call site, which still passes only logo candidates, is unchanged; Classic warms the copy of
    /// those items and gets the rest from the commit-time request).
    static func warmRow(source: String,
                        item: MetaPreview?,
                        done: inout Set<String>,
                        logoCandidates: () -> [MetaPreview],
                        prefetch: () -> [String]) {
        guard item != nil, done.insert(source).inserted else { return }
        ArtworkStore.prefetch(prefetch().compactMap(URL.init(string:)))
        let rowItems = logoCandidates()
        guard !rowItems.isEmpty else { return }
        let candidates = rowItems.filter { TitleLogoStore.isLookupCandidate($0.logo) }
        if !candidates.isEmpty { TitleLogoStore.shared.lookupIfNeeded(candidates) }
        StageLocalizedCopyStore.shared.prefetch(rowItems)
    }

    /// Wave H: warm a collection row's folder artwork when the ROW appears. Shares the per-row
    /// dedup set with `warmRow`, so a row pays for its warm-up exactly once per lifetime whichever
    /// of the two events happens first.
    static func warmCollection(_ collection: NuvioCollection, done: inout Set<String>) {
        guard done.insert(collection.id).inserted else { return }
        ArtworkStore.prefetch(collectionArtURLs(collection).compactMap(URL.init(string:)))
    }
}
