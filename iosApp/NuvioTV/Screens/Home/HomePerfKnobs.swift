import Foundation

/// Batch P Wave 2 (W2-5 c) / Wave 3 (W3-2): the one A/B knob that survives for the device rig's
/// Stage walk. The strip edge-mask and page-opacity knobs were disproved and are gone. Launch-latched
/// (`static let`, read once) and readable in DEBUG and Release, because the rig walks Release.
/// `UserDefaults.bool(forKey:)` coerces the `YES` of a `-debug.homeNoCardDepth YES` launch
/// argument. Defaults off.
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
