import Foundation

/// FEAT-82 (Steven, rc11 verdict 2026-10-21: "the icons are still not all the same size"): the
/// Detail action row's secondary buttons are the same size (the rig measured equal platters), but the
/// SF Symbols inside them are not: measured on the Living Room box in his configuration (Rounded,
/// system font, Medium+), at rest, `play.rectangle.fill` draws 28 × 22 pt, `checkmark.circle` 25 × 25
/// and `plus` 20 × 20 — a symbol with its own ring reads bigger than a bare stroke glyph at the same
/// point size. These factors bring every icon-only glyph to the circle's 25 pt optical size. Applied
/// as a `scaleEffect` on the icon of an icon-only label only, so no layout changes (the platters,
/// the FEAT-82 square side and Play are untouched) and text labels (Classic) keep the symbols as the
/// system sizes them beside their titles.
nonisolated enum DetailActionGlyphScale {
    /// The optical size every secondary glyph is brought to, in points.
    static let target: CGFloat = 25

    /// Measured optical size (the longer side of the drawn glyph's bounding box) per symbol, pt.
    static let measured: [String: CGFloat] = [
        "play.rectangle.fill": 28,
        "checkmark.circle": 25,
        "checkmark.circle.fill": 25,
        "plus": 20,
        // A bare checkmark is the same stroke class as `plus` (unmeasured; treated alike).
        "checkmark": 20,
    ]

    /// The scale factor for `symbol`; 1 for anything not in the table (`play.fill`, `shuffle`, …).
    static func scale(for symbol: String) -> CGFloat {
        guard let size = measured[symbol], size > 0 else { return 1 }
        return target / size
    }
}
