import Foundation

/// FEAT-82 (review r3 P2-1): every SF Symbol name the Detail action row draws, in one place, so
/// `DetailView`'s buttons and `DetailActionGlyphScale`'s table read the same constants. A glyph that
/// is added to the row without a constant here, or to `secondary` without a table entry, fails
/// `DetailActionGlyphScaleTests` instead of shipping unscaled.
nonisolated enum DetailActionSymbol {
    /// Play / Resume (the primary button keeps its label in Cinematic and is never scaled).
    static let play = "play.fill"
    /// Watch Trailer.
    static let trailer = "play.rectangle.fill"
    /// Mark Watched: off / on.
    static let watchedOff = "checkmark.circle"
    static let watchedOn = "checkmark.circle.fill"
    /// Add to Library / In Library.
    static let libraryAdd = "plus"
    static let libraryIn = "checkmark"
    /// Shuffle: off / on (`DetailActiveGlyph.shuffleOffGlyph` / `shuffleOnGlyph` alias these).
    static let shuffleOff = "shuffle"
    static let shuffleOn = "shuffle.circle.fill"
    /// Start Over (Cinematic, titles with a saved position).
    static let startOver = "arrow.counterclockwise"

    /// Every SECONDARY icon-only glyph: in Cinematic `usesIconOnlyLabel(primary: false)` is always
    /// true, so each of these renders as a bare symbol and needs a `DetailActionGlyphScale` entry.
    static let secondary: [String] = [
        trailer, watchedOff, watchedOn, libraryAdd, libraryIn, shuffleOff, shuffleOn, startOver,
    ]
}

/// FEAT-82 (Steven, rc11 verdict 2026-10-21: "the icons are still not all the same size"): the
/// Detail action row's secondary buttons are the same size (the rig measured equal platters), but the
/// SF Symbols inside them are not: measured on the Living Room box in his configuration (Rounded,
/// system font, Medium+), at rest, `play.rectangle.fill` draws 28 × 22 pt, `checkmark.circle` 25 × 25
/// and `plus` 20 × 20 — a symbol with its own ring reads bigger than a bare stroke glyph at the same
/// point size. These factors bring every icon-only glyph to the circle's 25 pt optical size. Applied
/// as a `scaleEffect` on the icon of an icon-only label only, so no layout changes (the platters,
/// the FEAT-82 square side and Play are untouched) and text labels (Classic) keep the symbols as the
/// system sizes them beside their titles. Never `.font(.system(size:))`: the contract bans a point
/// size at a call site, and a static `scaleEffect` is not a focus chain.
nonisolated enum DetailActionGlyphScale {
    /// The optical size every secondary glyph is brought to, in points.
    static let target: CGFloat = 25

    /// Optical size (the longer side of the drawn glyph's bounding box) per symbol, pt, keyed by
    /// `DetailActionSymbol`. Entries in `unmeasured` carry `target` (scale 1) until the box gives a
    /// number: replace the value, delete the symbol from `unmeasured`, and update
    /// `testUnmeasuredSymbolsAreExactlyTheListedThree`.
    static let measured: [String: CGFloat] = [
        DetailActionSymbol.trailer: 28,
        DetailActionSymbol.watchedOff: 25,
        DetailActionSymbol.watchedOn: 25,
        DetailActionSymbol.libraryAdd: 20,
        // MEASURE: In Library `checkmark` (rc11 guessed 20 / x1.25, which may overshoot): a film with
        // In Library on, Steven's config, rest crop as R0 `21-detail-rest`.
        DetailActionSymbol.libraryIn: target,
        // MEASURE: Shuffle off `shuffle` (a series with the global switch on, Shuffle off).
        DetailActionSymbol.shuffleOff: target,
        // MEASURE: Shuffle on `shuffle.circle.fill` (same series, Shuffle on; ringed like
        // `checkmark.circle`, so likely ~25).
        DetailActionSymbol.shuffleOn: target,
        // Start Over, measured 2026-10-22 on the box (Animals after an mpv session, Cinematic,
        // Steven's config): 21.5 × 26 pt → the 26 pt box is the optical size.
        DetailActionSymbol.startOver: 26,
    ]

    /// The `measured` entries that are still the provisional `target` (scale 1), not a box reading.
    static let unmeasured: Set<String> = [
        DetailActionSymbol.libraryIn, DetailActionSymbol.shuffleOff, DetailActionSymbol.shuffleOn,
    ]

    /// The scale factor for `symbol`; 1 for anything not in the table (`play.fill`, a new symbol).
    static func scale(for symbol: String) -> CGFloat {
        guard let size = measured[symbol], size > 0 else { return 1 }
        return target / size
    }
}
