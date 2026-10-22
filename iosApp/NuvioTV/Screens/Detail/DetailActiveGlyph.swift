import SwiftUI

/// W3-17 (BUG-205, Steven rc11: "the Watched icon returns to its rest colour later than its
/// neighbours"): the on/off state of Detail's compact action buttons (Mark Watched, Add to Library,
/// Shuffle) is carried by the GLYPH, not by an accent tint on the glass.
///
/// Why. Those three buttons share one `.glass` style, padding, label and font with Trailer/Start
/// Over, inside one `GlassEffectContainer`; the only difference between them is
/// `.tint(isActive ? accent : nil)`. A tinted system glass restores its resting fill more slowly
/// once focus leaves (and Steven's accent is White, which makes the tinted glass bright and the
/// crossfade easy to see). A foreground colour keyed on the focus environment flips with the
/// platter and has no crossfade of its own.
///
/// The mechanism is `ProminentAccentLabel`'s (FlatControlStyles.swift): an explicit
/// `foregroundStyle` disables the system's automatic label flip, so BOTH states are set by hand,
/// keyed on `\.isFocused`, which is proven inside system button styles (`.glass`,
/// `.glassProminent`, `.borderedProminent`):
///
/// - focused: the on-platter ink (`#0D0D0D`, `ProminentAccentLabel`'s dark), active or not;
/// - at rest and active: the accent colour;
/// - at rest and inactive: the normal label colour (`Theme.Palette.textPrimary`), or, beside a
///   LIGHT accent, the secondary label colour (`Theme.Palette.textSecondary`).
///
/// Review r1 P2-1 (the White accent). White's accent (`#F5F5F5`) and the normal label colour
/// (`Color.primary`, `#FFFFFF` on the dark scheme) are the same white on the glass, so with the
/// colour rule alone active and inactive looked identical at rest, and under focus both are the ink.
/// Two halves close it:
/// - colour: an accent whose luminance is above `Theme.Palette.lightAccentLuminance` (White only;
///   Amber, the brightest saturated accent, is about 0.6) dims the INACTIVE label to the secondary
///   colour, so the active accent stands out at rest. Every other accent keeps the rule above
///   unchanged;
/// - shape: every one of the three buttons carries its state in its glyph too, so the cue survives
///   focus (where both states are the ink). Watched (`checkmark.circle` / `.fill`) and Library
///   (`plus` / `checkmark`) already swap; Shuffle drew one `shuffle` for both states and is
///   icon-only in Cinematic, so it takes `shuffleOnGlyph` / `shuffleOffGlyph` through
///   `glyph(active:onGlyph:offGlyph:)`.
///
/// Use on the LABEL of the button (inside its label closure), never on the `Button`:
///
///     Button { model.toggleWatched() } label: {
///         actionButtonPadding(
///             actionLabel(...).font(Theme.Font.meta).detailActiveGlyph(active: model.isWatched),
///             horizontal: Theme.Spacing.md)
///     }
///
/// and drop the `.tint(...)` on that button. The modifier colours everything in the label (the
/// glyph and, in Classic's text labels, the title). Shuffle's wiring (owner, `DetailView.swift`):
///
///     actionLabel(
///         model.shuffleSettings.enabled ? "Shuffle On" : "Shuffle",
///         systemImage: DetailActiveGlyph.glyph(active: model.shuffleSettings.enabled,
///                                              onGlyph: DetailActiveGlyph.shuffleOnGlyph,
///                                              offGlyph: DetailActiveGlyph.shuffleOffGlyph)
///     )
///     .font(Theme.Font.meta)
///     .detailActiveGlyph(active: model.shuffleSettings.enabled)
nonisolated enum DetailActiveGlyph {
    /// The on-platter ink: `ProminentAccentLabel`'s focused colour (`Color(hex: 0x0D0D0D)`), spelled
    /// out in sRGB so this stays usable from a nonisolated context.
    static let inkOnPlatter = Color(.sRGB, red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 13.0 / 255.0, opacity: 1)

    /// The normal label colour of a button on a dark screen (`Theme.Palette.textPrimary`).
    static let restingLabel = Color.primary

    /// Review r1 P2-1: the inactive label colour beside a light accent, the repo's secondary label
    /// token (`Theme.Palette.textSecondary`, `Color.secondary`), spelled out here so this stays
    /// usable from a nonisolated context.
    static let dimmedRestingLabel = Color.secondary

    /// Shuffle's state glyphs (review r1 P2-1): one `shuffle` symbol for both states carried no
    /// state under focus or in Cinematic's icon-only label.
    static let shuffleOnGlyph = "shuffle.circle.fill"
    static let shuffleOffGlyph = "shuffle"

    /// The glyph colour for one state. Focus wins outright (the platter is near-white, and the
    /// White theme's accent would vanish on it), then the accent for an active button at rest, else
    /// the normal label colour, dimmed to the secondary colour beside a light accent. Pure, so the
    /// table is tested without a view.
    static func color(active: Bool, focused: Bool, accent: Color) -> Color {
        if focused { return inkOnPlatter }
        if active { return accent }
        return isLight(accent) ? dimmedRestingLabel : restingLabel
    }

    /// The SF Symbol for one state: `onGlyph` when active, else `offGlyph`. Paired with
    /// `detailActiveGlyph(active:)` on the same label, so a button carries its state in its shape
    /// as well as its colour (the shape is the only cue under focus).
    static func glyph(active: Bool, onGlyph: String, offGlyph: String) -> String {
        active ? onGlyph : offGlyph
    }

    /// Whether `accent` is light enough to read as the resting label: its luminance is above
    /// `Theme.Palette.lightAccentLuminance`, the same threshold (and the same strict comparison)
    /// `Theme.Palette.onColor(forFillHex:)` uses to give a fill dark ink (review r2 P3-3). White
    /// (`#F5F5F5`) is about 0.96; Amber, the brightest saturated accent, about 0.6; Ocean about 0.47.
    static func isLight(_ accent: Color) -> Bool {
        luminance(of: accent) > Theme.Palette.lightAccentLuminance
    }

    /// `accent`'s luminance on `Theme.Palette.luminance(fromHexString:)`'s scale, from its resolved
    /// sRGB components (the gamma-encoded values `Color(hex:)` was built from, as `CardDepthRGBA`
    /// reads them; checked against the hex luminance in `DetailActiveGlyphTests`). The theme accents
    /// are fixed sRGB colours, so the environment they resolve in does not matter.
    static func luminance(of accent: Color) -> Double {
        let resolved = accent.resolve(in: EnvironmentValues())
        func unit(_ component: Float) -> Double { min(max(Double(component), 0), 1) }
        return 0.2126 * unit(resolved.red) + 0.7152 * unit(resolved.green) + 0.0722 * unit(resolved.blue)
    }
}

/// See `DetailActiveGlyph`. Reads `\.isFocused` from the label's environment.
struct DetailActiveGlyphModifier: ViewModifier {
    let active: Bool
    let accent: Color
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.foregroundStyle(DetailActiveGlyph.color(active: active, focused: isFocused, accent: accent))
    }
}

extension View {
    /// Colours an action button's label by state (active at rest = accent, focused = the on-platter
    /// ink, inactive = the normal label colour, or the secondary one beside a light accent). Apply
    /// inside the button's label closure and drop the button's `.tint(...)`. A button whose glyph
    /// does not already change with its state picks it with
    /// `DetailActiveGlyph.glyph(active:onGlyph:offGlyph:)`. See `DetailActiveGlyph`.
    func detailActiveGlyph(active: Bool, accent: Color = Theme.Palette.accent) -> some View {
        modifier(DetailActiveGlyphModifier(active: active, accent: accent))
    }
}
