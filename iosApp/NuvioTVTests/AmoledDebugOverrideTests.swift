import XCTest
import SharedCore
@testable import NuvioTV

/// harness-w4 (2026-10-23): `-debug.amoledEnabledOverride YES|NO` sets OLED True Black for a UI leg
/// (`StageGate1EvidenceTests.testOledBarEvidence`) without the synced `amoled_enabled_<profile>` key.
/// The override must read through `ThemeSettingsRepository.amoledEnabled` (what `AppThemeModel`, the
/// ambient wash and Settings read) while the persisted setting, every `amoled_enabled*` defaults key
/// and the theme sync payload stay exactly as they were. The TMDB seam's twin
/// (`TmdbDebugOverrideTests`).
final class AmoledDebugOverrideTests: XCTestCase {

    func testDebugKeyName() {
        XCTAssertEqual(AmoledDebugOverride.debugKey, "debug.amoledEnabledOverride")
    }

    func testDebugOverrideReadsOnlyWhenPresent() throws {
        let suite = "AmoledDebugOverrideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(AmoledDebugOverride.debugEnabledOverride(defaults), "absent: the persisted setting decides")
        defaults.set(true, forKey: AmoledDebugOverride.debugKey)
        #if DEBUG
        XCTAssertEqual(AmoledDebugOverride.debugEnabledOverride(defaults), true)
        defaults.set(false, forKey: AmoledDebugOverride.debugKey)
        XCTAssertEqual(AmoledDebugOverride.debugEnabledOverride(defaults), false)
        #else
        XCTAssertNil(AmoledDebugOverride.debugEnabledOverride(defaults))
        #endif
    }

    /// Every `amoled_enabled*` key in the standard defaults (all domains), values as text.
    private func amoledDefaults() -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("amoled_enabled") {
            out[key] = "\(value)"
        }
        return out
    }

    /// The theme store's sync export as text (key → encoded value).
    private func payload() -> [String: String] {
        // Read through NSDictionary: the payload's values include nested JSON objects (the sync
        // encoders wrap values), which the bridged `[String: JsonElement]` view cannot cast.
        let raw = ThemeSettingsStoreProvider.shared.store.exportToSyncPayload() as NSDictionary
        var out: [String: String] = [:]
        for case let (key as String, value) in raw { out[key] = "\(value)" }
        return out
    }

    private func publishedAmoled() -> Bool {
        (ThemeSettingsRepository.shared.amoledEnabled.value_ as? KotlinBoolean)?.boolValue ?? false
    }

    func testOverrideReadsThroughWhileThePersistedSettingAndPayloadStayUnchanged() {
        let repository = ThemeSettingsRepository.shared
        let store = ThemeSettingsStoreProvider.shared.store
        let previousOverride = repository.currentDebugAmoledEnabledOverride()
        defer { repository.setDebugAmoledEnabledOverride(value: previousOverride) }
        repository.setDebugAmoledEnabledOverride(value: nil)
        repository.ensureLoaded()

        let storedBefore = store.loadAmoledEnabled()?.boolValue
        let keysBefore = amoledDefaults()
        let payloadBefore = payload()
        let amoledBefore = publishedAmoled()
        XCTAssertEqual(amoledBefore, storedBefore ?? false, "without the override the accessor reads the persisted value")
        // The opposite of the profile's own value, so the read-through is observable.
        let forced = !amoledBefore

        repository.setDebugAmoledEnabledOverride(value: KotlinBoolean(value: forced))
        XCTAssertEqual(publishedAmoled(), forced, "the override must read through ThemeSettingsRepository.amoledEnabled")
        XCTAssertEqual(store.loadAmoledEnabled()?.boolValue, storedBefore, "the persisted amoled_enabled must not change")
        XCTAssertEqual(amoledDefaults(), keysBefore, "no amoled_enabled* defaults key may be written")
        XCTAssertEqual(payload(), payloadBefore, "the theme sync payload must keep the persisted value")

        // A profile reload (what a switch or a remote apply does) keeps the override and writes nothing.
        repository.onProfileChanged()
        XCTAssertEqual(publishedAmoled(), forced, "the override must survive a reload from storage")
        XCTAssertEqual(amoledDefaults(), keysBefore, "a reload under the override must write nothing")
        XCTAssertEqual(payload(), payloadBefore)

        repository.setDebugAmoledEnabledOverride(value: nil)
        XCTAssertEqual(publishedAmoled(), amoledBefore, "clearing the override restores the persisted value")
        XCTAssertEqual(amoledDefaults(), keysBefore)
        XCTAssertEqual(payload(), payloadBefore)
    }
}
