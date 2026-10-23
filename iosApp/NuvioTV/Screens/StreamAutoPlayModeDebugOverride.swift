import Foundation
import SharedCore

/// DEBUG harness knob (harness-w4, 2026-10-23): `-debug.streamAutoPlayModeOverride <MODE>` sets the
/// stream auto-play mode (`MANUAL`, `FIRST_STREAM` = "Auto-Play Best Source", `REGEX_MATCH`) for
/// this launch only. test72 (first-play auto mode and hold-Play) needs FIRST_STREAM on the signed-in
/// fixture; the only other way in was `-stream_auto_play_mode_<profile> FIRST_STREAM`, a SYNCED key
/// (`PlayerSettingsStorage` exports it from NSUserDefaults, argument domain included) that a
/// settings push would carry into the account's payload.
///
/// The TMDB seam's twin (`TmdbDebugOverride`): the name is handed to the shared
/// `PlayerSettingsRepository` before any repository loads; the repository consults it BEFORE the
/// persisted `stream_auto_play_mode`, keeps it in memory, never writes it, and the sync export reads
/// storage, so the payload keeps the persisted value. nil when absent or blank, and always nil in
/// Release. A name that is not a mode is ignored by the repository (the persisted value decides).
nonisolated enum StreamAutoPlayModeDebugOverride {
    static let debugKey = "debug.streamAutoPlayModeOverride"

    /// The launch's override (the shared enum's name, as typed), or nil when the key is absent or
    /// blank (or in Release).
    static func debugModeOverride(_ defaults: UserDefaults = .standard) -> String? {
        #if DEBUG
        guard let raw = defaults.string(forKey: debugKey)?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        return raw
        #else
        return nil
        #endif
    }

    /// Hands the override to the shared repository. Called once from `NuvioTVApp.init`, before any
    /// repository is accessed. A no-op in Release and when the key is absent.
    static func apply(_ defaults: UserDefaults = .standard) {
        #if DEBUG
        guard let name = debugModeOverride(defaults) else { return }
        PlayerSettingsRepository.shared.setDebugStreamAutoPlayModeOverride(modeName: name)
        #endif
    }
}
