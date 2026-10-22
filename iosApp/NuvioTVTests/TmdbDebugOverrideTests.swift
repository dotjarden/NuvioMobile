import XCTest
import SharedCore
@testable import NuvioTV

/// ui-legs (2026-10-22): `-debug.tmdbEnabledOverride YES|NO` turns TMDB on for a UI leg without the
/// synced `tmdb_enabled_<profile>` key. The override must read through the TMDB-enabled accessor
/// (`TmdbSettingsRepository.snapshot().enabled`) while the persisted setting, every `tmdb_*`
/// defaults key and the sync payload stay exactly as they were.
final class TmdbDebugOverrideTests: XCTestCase {

    func testDebugKeyName() {
        XCTAssertEqual(TmdbDebugOverride.debugKey, "debug.tmdbEnabledOverride")
    }

    func testDebugOverrideReadsOnlyWhenPresent() throws {
        let suite = "TmdbDebugOverrideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(TmdbDebugOverride.debugEnabledOverride(defaults), "absent: the persisted setting decides")
        defaults.set(true, forKey: TmdbDebugOverride.debugKey)
        #if DEBUG
        XCTAssertEqual(TmdbDebugOverride.debugEnabledOverride(defaults), true)
        defaults.set(false, forKey: TmdbDebugOverride.debugKey)
        XCTAssertEqual(TmdbDebugOverride.debugEnabledOverride(defaults), false)
        #else
        XCTAssertNil(TmdbDebugOverride.debugEnabledOverride(defaults))
        #endif
    }

    /// Every `tmdb_*` key in the standard defaults (all domains), values as text.
    private func tmdbDefaults() -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("tmdb_") {
            out[key] = "\(value)"
        }
        return out
    }

    /// The sync export of the TMDB settings as text (key → encoded value).
    private func payload() -> [String: String] {
        TmdbSettingsStorage.shared.exportToSyncPayload().mapValues { $0.description }
    }

    func testOverrideReadsTrueWhileThePersistedSettingAndPayloadStayUnchanged() {
        let repository = TmdbSettingsRepository.shared
        let storage = TmdbSettingsStorage.shared
        let previousOverride = repository.currentDebugEnabledOverride()
        defer { repository.setDebugEnabledOverride(value: previousOverride) }
        repository.setDebugEnabledOverride(value: nil)

        let storedBefore = storage.loadEnabled()?.boolValue
        let keysBefore = tmdbDefaults()
        let payloadBefore = payload()
        let enabledBefore = repository.snapshot().enabled
        XCTAssertEqual(enabledBefore, storedBefore ?? false, "without the override the accessor reads the persisted value")

        repository.setDebugEnabledOverride(value: KotlinBoolean(value: true))
        XCTAssertTrue(repository.snapshot().enabled, "the override must read through the TMDB-enabled accessor")
        XCTAssertEqual(storage.loadEnabled()?.boolValue, storedBefore, "the persisted tmdb_enabled must not change")
        XCTAssertEqual(tmdbDefaults(), keysBefore, "no tmdb_* defaults key may be written")
        XCTAssertEqual(payload(), payloadBefore, "the sync payload must keep the persisted value")

        // A profile reload (what a switch or a remote apply does) keeps the override and writes nothing.
        repository.onProfileChanged()
        XCTAssertTrue(repository.snapshot().enabled, "the override must survive a reload from storage")
        XCTAssertEqual(tmdbDefaults(), keysBefore, "a reload under the override must write nothing")

        repository.setDebugEnabledOverride(value: nil)
        XCTAssertEqual(repository.snapshot().enabled, enabledBefore, "clearing the override restores the persisted value")
        XCTAssertEqual(tmdbDefaults(), keysBefore)
        XCTAssertEqual(payload(), payloadBefore)
    }
}
