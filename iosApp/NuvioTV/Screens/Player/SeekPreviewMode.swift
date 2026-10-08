import Foundation

/// Player P3: where the seek preview gets its pictures, one switch for both engines (Developer ›
/// "Seek Preview Frames (A/B)"). Read once per playback, so a change applies to the next one.
///
/// - `off`: no pictures at all. The mpv harvest and decoder stay off, and the native engine's
///   loopback master carries no `EXT-X-I-FRAME-STREAM-INF` (byte for byte the pre-P3 master).
/// - `harvest` (default, also for an unset or unknown value): the P2 harvest saves frames the
///   viewer has played; the native engine publishes its I-frame rendition for FF/RW scan.
/// - `decode`: harvest, plus the mpv keyframe thumbnailer for ground not watched yet.
nonisolated enum SeekPreviewMode: String, CaseIterable, Sendable {
    case off, harvest, decode

    static let defaultsKey = "debug.seekPreviewMode"
    static let defaultMode: SeekPreviewMode = .harvest

    /// nil, empty or unknown → `defaultMode`.
    static func parse(_ raw: String?) -> SeekPreviewMode {
        raw.flatMap(Self.init(rawValue:)) ?? defaultMode
    }

    static func current(_ defaults: UserDefaults = .standard) -> SeekPreviewMode {
        parse(defaults.string(forKey: defaultsKey))
    }

    /// The native engine publishes the `EXT-X-I-FRAMES-ONLY` rendition.
    var allowsIFrames: Bool { self != .off }
    /// The mpv engine saves played frames (P2 harvest; its own crash guard still applies).
    var allowsHarvest: Bool { self != .off }
    /// The mpv engine runs the keyframe thumbnailer for unwatched ground.
    var allowsDecode: Bool { self == .decode }

    /// Picker label (Developer row).
    var displayName: String {
        switch self {
        case .off: return String(localized: "Off")
        case .harvest: return String(localized: "Harvest Only")
        case .decode: return String(localized: "Harvest + Decode")
        }
    }
}
