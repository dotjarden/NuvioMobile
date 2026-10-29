import SwiftUI

/// The four focus-look settings every card reads (`accent_focus_ring`, `no_zoom_on_focus`,
/// `focus_ring_poster_color`, `depth_rail_poster_color`), read ONCE at the app root and passed down
/// as one Equatable value. Each card used to hold its own `@AppStorage` for all four, in up to five
/// nested views: ~10 UserDefaults observers per realized card, all re-rendering on any flip.
struct FocusAppearance: Equatable {
    var accentFocusRing = false
    var noZoomOnFocus = false
    var ringTakesPosterColor = false
    var depthTakesPosterColor = false

    /// The stored values, for views hosted outside the root's environment (a UIKit-presented host).
    static func stored(_ defaults: UserDefaults = .standard) -> FocusAppearance {
        FocusAppearance(
            accentFocusRing: defaults.bool(forKey: "accent_focus_ring"),
            noZoomOnFocus: defaults.bool(forKey: "no_zoom_on_focus"),
            ringTakesPosterColor: defaults.bool(forKey: "focus_ring_poster_color"),
            depthTakesPosterColor: defaults.bool(forKey: "depth_rail_poster_color")
        )
    }
}

private struct FocusAppearanceKey: EnvironmentKey {
    /// Computed, not stored: a view with no root above it still reads the real settings.
    static var defaultValue: FocusAppearance { .stored() }
}

extension EnvironmentValues {
    var focusAppearance: FocusAppearance {
        get { self[FocusAppearanceKey.self] }
        set { self[FocusAppearanceKey.self] = newValue }
    }
}

/// Owns the four `@AppStorage` reads; put it once at the root of a SwiftUI tree.
struct ProvidesFocusAppearance: ViewModifier {
    @AppStorage("accent_focus_ring") private var accentFocusRing = false
    @AppStorage("no_zoom_on_focus") private var noZoomOnFocus = false
    @AppStorage("focus_ring_poster_color") private var ringTakesPosterColor = false
    @AppStorage("depth_rail_poster_color") private var depthTakesPosterColor = false

    func body(content: Content) -> some View {
        content.environment(\.focusAppearance, FocusAppearance(
            accentFocusRing: accentFocusRing,
            noZoomOnFocus: noZoomOnFocus,
            ringTakesPosterColor: ringTakesPosterColor,
            depthTakesPosterColor: depthTakesPosterColor
        ))
    }
}

extension View {
    /// See `ProvidesFocusAppearance`.
    func providesFocusAppearance() -> some View { modifier(ProvidesFocusAppearance()) }
}
