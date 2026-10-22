import Foundation

/// Batch P Wave 2 (W2-5 c) / Wave 3 (W3-2, W3-13): the A/B knobs that survive for the device rig's
/// walks. The strip edge-mask and page-opacity knobs were disproved and are gone. Launch-latched
/// (`static let`, read once) and readable in DEBUG and Release, because the rig walks Release.
/// `UserDefaults.bool(forKey:)` coerces the `YES` of a `-debug.homeNoCardDepth YES` launch
/// argument, and `integer(forKey:)` the `2` of a `-debug.cardDepthRender 2`. Both default off.
///
///   `-debug.homeNoCardDepth YES`      `CardDepthModifier` draws no overlay (every surface).
///   `-debug.cardDepthRender 0|1|2`    W3-13: how `CardDepthOverlay` rasterises Card Depth
///                                     (`CardDepthRender`); 0 or any other value = today's live layers.
///                                     Any value passed, 0 included, logs one line.
///
/// W3-13's knob exists for the R1 rig walks only: the owner picks the shipping variant from them,
/// then deletes the knob and the losing variants (W3-2's pattern).
nonisolated enum HomePerfKnobs {
    static let noCardDepthKey = "debug.homeNoCardDepth"
    static let cardDepthRenderKey = "debug.cardDepthRender"

    static let noCardDepth: Bool = resolve(noCardDepthKey)
    /// Logs one `[HomePerfKnobs] cardDepthRender=<n>` line whenever the launch passes the knob, 0
    /// included (review r1 P3-4), so a walk's console proves which variant it measured: a walk at 0
    /// passes `-debug.cardDepthRender 0` and gets its line, and a mistyped argument (no line, or a
    /// flagged value) no longer reads like a clean 0. See `cardDepthRenderLogLine`.
    static let cardDepthRender: CardDepthRender = {
        let variant = resolveCardDepthRender(cardDepthRenderKey)
        if let line = cardDepthRenderLogLine(cardDepthRenderKey) { NSLog("%@", line) }
        return variant
    }()

    /// W3-13: the three ways `CardDepthOverlay` can pay for its gradients. All three share the two
    /// structural fixes (the rail hidden by opacity on focus, white rail × tint by multiply); they
    /// differ only in where the pixels come from.
    enum CardDepthRender: Int, CaseIterable, Sendable {
        /// 0: the live SwiftUI layers, CoreGraphics filling each card's gradients (today's raster).
        case live = 0
        /// 1: the same layers inside one `.drawingGroup()`: Metal renders them into one offscreen
        /// texture per card (about 1 MB at 2x; watch jetsam with ~40 cards mounted).
        case drawingGroup = 1
        /// 2: white rail and sheen bitmaps from `CardDepthRasterCache`, rendered once per key with
        /// `UIGraphicsImageRenderer` and shared by every card that draws the same key.
        case rasterCache = 2
    }

    /// The resolver the latched value uses; `defaults` is injectable for the unit test.
    static func resolve(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    /// The render variant for `key`: the integer the argument domain carries (`"2"` → 2), and the
    /// live layers for an absent, unparsable or out-of-range value.
    static func resolveCardDepthRender(_ key: String, defaults: UserDefaults = .standard) -> CardDepthRender {
        CardDepthRender(rawValue: defaults.integer(forKey: key)) ?? .live
    }

    /// The knob's launch line: nil when `key` is absent; else `[HomePerfKnobs] cardDepthRender=<n>`
    /// with the variant actually resolved, plus ` (unparsed value "<raw>")` when the raw value is
    /// not exactly that variant's number (`YES`, `abc`, `5`, `2.5`), so a typo is visible in the
    /// walk's console rather than silently measuring variant 0.
    static func cardDepthRenderLogLine(_ key: String, defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.object(forKey: key) else { return nil }
        let variant = resolveCardDepthRender(key, defaults: defaults)
        let text = "\(raw)".trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = Int(text).flatMap(CardDepthRender.init(rawValue:)) == variant
        return "[HomePerfKnobs] cardDepthRender=\(variant.rawValue)" + (clean ? "" : " (unparsed value \"\(text)\")")
    }
}
