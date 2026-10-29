import SwiftUI

/// BUG-180 (Steven rc7): every surface the player draws over the video (top panel, pause card,
/// Stream Info card, action chips and captions, the aspect flash, the transport pills) used live
/// Liquid Glass plus a soft shadow. Over the mpv Metal layer at 4K HDR/DV both are re-sampled from
/// the video on every frame, and with `vulkan-swap-mode=fifo` the slow composite stalls mpv: the film
/// behind an open menu dropped to ~10 fps and the menus themselves stuttered. Player surfaces now use
/// a solid translucent fill with a hairline edge and no shadow; nothing here reads the pixels below.
/// Player-only: the rest of the app keeps its glass.
enum PlayerSurfaceStyle {
    /// Fill for cards and the top panel. 0.72 black keeps white text at roughly 9:1 even over a pure
    /// white frame (the old 0.45 glass tint measured about 3.4:1 there before its blur).
    static let fill = Color.black.opacity(0.72)
    /// Lighter fill for the small capsules (chips, captions, flash, resting pills), which sit over the
    /// picture's lower third and are glanced at, not read at length.
    static let chipFill = Color.black.opacity(0.62)
    /// Hairline edge that separates the surface from a dark scene, where the fill alone disappears.
    static let stroke = Color.white.opacity(0.08)
    static let strokeWidth: CGFloat = 1
}

/// Fill + hairline stroke in `shape`. Use instead of `.glassEffect(…)` + `.shadow(…)` on anything the
/// player draws over the video.
struct PlayerSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Color = PlayerSurfaceStyle.fill

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(PlayerSurfaceStyle.stroke, lineWidth: PlayerSurfaceStyle.strokeWidth))
    }
}

extension View {
    /// BUG-180: the player's non-glass surface (see `PlayerSurfaceStyle`).
    func playerSurface<S: InsettableShape>(in shape: S, fill: Color = PlayerSurfaceStyle.fill) -> some View {
        modifier(PlayerSurface(shape: shape, fill: fill))
    }
}
