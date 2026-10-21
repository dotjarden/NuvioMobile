import Foundation

/// Batch P Wave 2 (W2-5 c): three A/B knobs for the device rig's Stage walk, each removing exactly
/// one rendering layer and nothing else. Launch-latched (`static let`, read once) and readable in
/// DEBUG and Release, because the rig walks Release. `UserDefaults.bool(forKey:)` coerces the
/// `YES` of a `-debug.homeNoStripEdgeMask YES` launch argument. All three default off.
///
///   `-debug.homeNoStripEdgeMask YES`  the strip's `StripEdgeMask` is not applied (`StripPager`).
///   `-debug.homeNoPageOpacity YES`    the strip pages' opacity `.visualEffect` is not applied.
///   `-debug.homeNoCardDepth YES`      `CardDepthModifier` draws no overlay (every surface).
nonisolated enum HomePerfKnobs {
    static let noStripEdgeMaskKey = "debug.homeNoStripEdgeMask"
    static let noPageOpacityKey = "debug.homeNoPageOpacity"
    static let noCardDepthKey = "debug.homeNoCardDepth"

    static let noStripEdgeMask: Bool = resolve(noStripEdgeMaskKey)
    static let noPageOpacity: Bool = resolve(noPageOpacityKey)
    static let noCardDepth: Bool = resolve(noCardDepthKey)

    /// The resolver the latched values use; `defaults` is injectable for the unit test.
    static func resolve(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}
