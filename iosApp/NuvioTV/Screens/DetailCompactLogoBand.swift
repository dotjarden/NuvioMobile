import CoreGraphics

/// D-3 (design review 2026-10-22, P3): FEAT-60's compact title logo sits in a fixed band at the top
/// of a scrolled Cinematic Detail page, and rows rest under it — the Parental Guide chips read
/// straight through the logo ("Frightening Scenes Moderate" under Animals, "Alcohol & Drugs /
/// Frightening Scenes" under The Simpsons). The logo now fades out while a row's LEAD — its heading,
/// and for a chip row like Parental Guide its chips — is inside the band, and back in once clear.
///
/// Only the lead counts, not the whole row: rows are 36 pt apart and the band is 72 pt tall, so a
/// whole-row test would find some row in the band at every rest and the logo would never show. A
/// card shelf's tail (cast names, poster bottoms) left above an anchored row sits under
/// `DetailTopScrim` and reads as scrolled away; a heading or a chip line does not.
///
/// The rows' content-space tops and heights come from `DetailRowAnchored` (layout-only changes,
/// the BUG-41 rule) and the content offset from the page's existing `onScrollGeometryChange`, so
/// the per-frame cost is this loop over at most nine rows inside a closure that already runs.
/// Pure so `DetailCompactLogoBandTests` can drive it without a scroll view.
/// `nonisolated` (the `DetailScrim` pattern): read from the scroll-geometry closure and the tests.
nonisolated enum DetailCompactLogoBand {
    /// The logo's top padding from the scroll view's top edge (`DetailCompactLogo`).
    static let topPadding: CGFloat = 36
    /// The logo's slot height (`DetailCompactLogo.slotHeight`).
    static let slotHeight: CGFloat = 72
    /// The band, in screen points from the scroll view's top edge: 36…108. Its bottom is
    /// `DetailRowAnchor.screenRest`, where an anchored row's top rests.
    static var bandTop: CGFloat { topPadding }
    static var bandBottom: CGFloat { topPadding + slotHeight }
    /// How deep into a row its lead reaches: a section title (38–42 pt by font), the 16 pt gap and
    /// one chip line (≈47 pt) — the Parental Guide row whole, the heading and first card edge of a
    /// shelf row.
    static let leadDepth: CGFloat = 112
    /// Review P2-2: how far above the band's bottom a row's top may rest and still not count. An
    /// anchored row rests at `screenRest` (= the band's bottom) give or take a fractional point or a
    /// small drift the anchor's verify pass does not correct, and its own heading must not hide the
    /// logo; a top more than this far above the bottom is a heading genuinely inside the slot.
    static let restTolerance: CGFloat = 16

    /// One row's frame in the scroll CONTENT's coordinate space (`DetailRowAnchor.contentSpace`).
    nonisolated struct Row: Equatable, Sendable {
        let top: CGFloat
        let height: CGFloat
    }

    /// What the page's hero-exit observer publishes: `heroGone` is FEAT-60's existing gate
    /// (`DetailCompactLogo.heroClearance`, unchanged); `bandBlocked` is the D-3 gate.
    nonisolated struct Gate: Equatable, Sendable {
        var heroGone = false
        var bandBlocked = false
    }

    /// True while any row's lead — `[top, top + min(height, leadDepth)]` on screen — overlaps the
    /// band. A row's screen top is `top − contentOffset` (`DetailRowAnchor.scrollTarget`'s doc).
    /// Edges touching the band do not count, and a top within `restTolerance` of the band's bottom
    /// does not either: an anchored row resting at (or just above) `screenRest` leaves it clear.
    static func blocked(rows: [Row], contentOffset: CGFloat,
                        bandTop: CGFloat = bandTop, bandBottom: CGFloat = bandBottom,
                        leadDepth: CGFloat = leadDepth, restTolerance: CGFloat = restTolerance) -> Bool {
        rows.contains { row in
            guard row.height > 0 else { return false }
            let screenTop = row.top - contentOffset
            let leadBottom = screenTop + min(row.height, leadDepth)
            return screenTop < bandBottom - restTolerance && leadBottom > bandTop
        }
    }

    /// The observer's whole decision: the band only matters once the hero has gone (the logo is
    /// hidden before that anyway), so it is not computed — and cannot flip — inside the hero.
    static func gate(heroGone: Bool, rows: [Row], contentOffset: CGFloat) -> Gate {
        Gate(heroGone: heroGone,
             bandBlocked: heroGone && blocked(rows: rows, contentOffset: contentOffset))
    }

    /// The logo shows only in the rows, past the hero, with the band clear.
    static func shows(inRows: Bool, gate: Gate) -> Bool {
        inRows && gate.heroGone && !gate.bandBlocked
    }
}
