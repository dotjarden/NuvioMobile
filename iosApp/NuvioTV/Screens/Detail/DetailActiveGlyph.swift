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
/// - at rest and inactive: the normal label colour (`Theme.Palette.textPrimary`).
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
/// glyph and, in Classic's text labels, the title).
nonisolated enum DetailActiveGlyph {
    /// The on-platter ink: `ProminentAccentLabel`'s focused colour (`Color(hex: 0x0D0D0D)`), spelled
    /// out in sRGB so this stays usable from a nonisolated context.
    static let inkOnPlatter = Color(.sRGB, red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 13.0 / 255.0, opacity: 1)

    /// The normal label colour of a button on a dark screen (`Theme.Palette.textPrimary`).
    static let restingLabel = Color.primary

    /// The glyph colour for one state. Focus wins outright (the platter is near-white, and the
    /// White theme's accent would vanish on it), then the accent for an active button at rest, else
    /// the normal label colour. Pure, so the table is tested without a view.
    static func color(active: Bool, focused: Bool, accent: Color) -> Color {
        if focused { return inkOnPlatter }
        return active ? accent : restingLabel
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
    /// ink, inactive = the normal label colour). Apply inside the button's label closure and drop
    /// the button's `.tint(...)`. See `DetailActiveGlyph`.
    func detailActiveGlyph(active: Bool, accent: Color = Theme.Palette.accent) -> some View {
        modifier(DetailActiveGlyphModifier(active: active, accent: accent))
    }
}
