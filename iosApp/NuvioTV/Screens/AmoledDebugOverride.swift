import Foundation
import SharedCore

/// DEBUG harness knob (harness-w4, 2026-10-23): `-debug.amoledEnabledOverride YES|NO` turns OLED
/// True Black on or off for this launch only. `StageGate1EvidenceTests.testOledBarEvidence` needs
/// both states on the signed-in fixture; the only other way in was `-amoled_enabled_<profile>`, a
/// SYNCED theme key (`TvOsThemeSettingsStore` exports it from NSUserDefaults, argument domain
/// included) that a settings push would carry into the account's payload.
///
/// The TMDB seam's twin (`TmdbDebugOverride`): the override is handed to the shared
/// `ThemeSettingsRepository` before any repository loads; the repository consults it BEFORE the
/// persisted `amoled_enabled`, keeps it in memory, never writes it, and the sync export reads
/// storage, so the payload keeps the persisted value. nil when absent, and always nil in Release.
nonisolated enum AmoledDebugOverride {
    static let debugKey = "debug.amoledEnabledOverride"

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
        ThemeSettingsRepository.shared.setDebugAmoledEnabledOverride(value: KotlinBoolean(value: value))
        #endif
    }
}
