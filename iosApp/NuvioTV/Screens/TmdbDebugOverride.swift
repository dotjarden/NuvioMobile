import Foundation
import SharedCore

/// DEBUG harness knob (ui-legs, 2026-10-22): `-debug.tmdbEnabledOverride YES|NO` turns TMDB
/// enrichment on or off for this launch only. The UI legs that walk Detail → a Cast card →
/// biography → Back (`DetailFocusReturnUITests`) need the Cast row, which exists only with TMDB
/// enabled on the profile; the only other way in was `-tmdb_enabled_<profile> YES`, a SYNCED key
/// that a launch argument would carry into the account's settings payload.
///
/// The override is handed to the shared `TmdbSettingsRepository` before any repository loads; the
/// repository consults it BEFORE the persisted `tmdb_enabled`, keeps it in memory, never writes
/// it, and the sync export reads storage, so the payload keeps the persisted value. Same
/// convention as `ProfileAutoEnter.debugEnabledOverride` (`-debug.rememberLastProfile`): nil when
/// absent, and always nil in Release.
nonisolated enum TmdbDebugOverride {
    static let debugKey = "debug.tmdbEnabledOverride"

    /// The launch's override, or nil when the key is absent (or in Release).
    static func debugEnabledOverride(_ defaults: UserDefaults = .standard) -> Bool? {
        #if DEBUG
        guard defaults.object(forKey: debugKey) != nil else { return nil }
        return defaults.bool(forKey: debugKey)
        #else
        return nil
        #endif
    }

    /// Hands the override to the shared repository. Called once from `NuvioTVApp.init`, before any
    /// repository is accessed. A no-op in Release and when the key is absent.
    static func apply(_ defaults: UserDefaults = .standard) {
        #if DEBUG
        guard let value = debugEnabledOverride(defaults) else { return }
        TmdbSettingsRepository.shared.setDebugEnabledOverride(value: KotlinBoolean(value: value))
        #endif
    }
}
