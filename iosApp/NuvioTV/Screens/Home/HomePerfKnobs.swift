import Foundation

/// Batch P Wave 2 (W2-5 c) / Wave 3 (W3-2, W3-13): the one A/B knob that survives for the device
/// rig's Stage walk. The strip edge-mask and page-opacity knobs were disproved and are gone, and so
/// is W3-13's `-debug.cardDepthRender 0|1|2`: its A/B was decided on the Apple TV (Release, Classic
/// Home, 20 down / 20 up: live layers 95 / 89 hitches, `.drawingGroup()` 84 / 85, raster cache 85;
/// Card Depth off 46-72), and the raster cache (`CardDepthRasterCache`) is the rendering since
/// Wave 3, because the live layers paid a CPU gradient rasterisation (`argb32_shade_axial_RGB`) on
/// every mount and focus move. Launch-latched (`static let`, read once) and readable in DEBUG and
/// Release, because the rig walks Release. `UserDefaults.bool(forKey:)` coerces the `YES` of a
/// `-debug.homeNoCardDepth YES` launch argument. Defaults off.
///
///   `-debug.homeNoCardDepth YES`      `CardDepthModifier` draws no overlay (every surface).
nonisolated enum HomePerfKnobs {
    static let noCardDepthKey = "debug.homeNoCardDepth"

    static let noCardDepth: Bool = resolve(noCardDepthKey)

    /// The resolver the latched value uses; `defaults` is injectable for the unit test.
    static func resolve(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}
