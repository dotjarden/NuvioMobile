import XCTest
import SharedCore
@testable import NuvioTV

/// harness-w4 (2026-10-23): `-debug.streamAutoPlayModeOverride <MODE>` turns Auto-Play Best Source
/// on for a UI leg (test72) without the synced `stream_auto_play_mode_<profile>` key. The override
/// must read through the published player settings (`PlayerSettingsRepository.uiState`, the value
/// the stream picker and Detail read) while the persisted setting, every `stream_auto_play_mode*`
/// defaults key and the sync payload stay exactly as they were. The TMDB seam's twin
/// (`TmdbDebugOverrideTests`).
final class StreamAutoPlayModeDebugOverrideTests: XCTestCase {

    func testDebugKeyName() {
        XCTAssertEqual(StreamAutoPlayModeDebugOverride.debugKey, "debug.streamAutoPlayModeOverride")
    }

    func testDebugOverrideReadsOnlyWhenPresent() throws {
        let suite = "StreamAutoPlayModeDebugOverrideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(StreamAutoPlayModeDebugOverride.debugModeOverride(defaults), "absent: the persisted setting decides")
        defaults.set("  ", forKey: StreamAutoPlayModeDebugOverride.debugKey)
        XCTAssertNil(StreamAutoPlayModeDebugOverride.debugModeOverride(defaults), "blank: the persisted setting decides")
        defaults.set("FIRST_STREAM", forKey: StreamAutoPlayModeDebugOverride.debugKey)
        #if DEBUG
        XCTAssertEqual(StreamAutoPlayModeDebugOverride.debugModeOverride(defaults), "FIRST_STREAM")
        #else
        XCTAssertNil(StreamAutoPlayModeDebugOverride.debugModeOverride(defaults))
        #endif
    }

    /// Every `stream_auto_play_mode*` key in the standard defaults (all domains), values as text.
    private func modeDefaults() -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("stream_auto_play_mode") {
            out[key] = "\(value)"
        }
        return out
    }

    /// The sync export of the player settings as text (key → encoded value).
    private func payload() -> [String: String] {
        // Read through NSDictionary: the payload's values include nested JSON objects (the sync
        // encoders wrap values), which the bridged `[String: JsonElement]` view cannot cast.
        let raw = PlayerSettingsStorage.shared.exportToSyncPayload() as NSDictionary
        var out: [String: String] = [:]
        for case let (key as String, value) in raw { out[key] = "\(value)" }
        return out
    }

    private func publishedMode() -> StreamAutoPlayMode? {
        (PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState)?.streamAutoPlayMode
    }

    func testOverrideReadsThroughWhileThePersistedSettingAndPayloadStayUnchanged() {
        let repository = PlayerSettingsRepository.shared
        let storage = PlayerSettingsStorage.shared
        let previousOverride = repository.currentDebugStreamAutoPlayModeOverride()
        defer { repository.setDebugStreamAutoPlayModeOverride(modeName: previousOverride?.name) }
        repository.setDebugStreamAutoPlayModeOverride(modeName: nil)
        repository.ensureLoaded()

        let storedBefore = storage.loadStreamAutoPlayMode()
        let keysBefore = modeDefaults()
        let payloadBefore = payload()
        let modeBefore = publishedMode()
        XCTAssertEqual(modeBefore?.name, storedBefore ?? StreamAutoPlayMode.manual.name,
                       "without the override the published mode is the persisted one")
        // Pick a mode the profile does not already have, so the read-through is observable.
        let forced = modeBefore == StreamAutoPlayMode.firstStream ? StreamAutoPlayMode.manual : StreamAutoPlayMode.firstStream

        repository.setDebugStreamAutoPlayModeOverride(modeName: forced.name)
        XCTAssertEqual(publishedMode(), forced, "the override must read through the published player settings")
        XCTAssertEqual(repository.currentDebugStreamAutoPlayModeOverride(), forced)
        XCTAssertEqual(storage.loadStreamAutoPlayMode(), storedBefore, "the persisted stream_auto_play_mode must not change")
        XCTAssertEqual(modeDefaults(), keysBefore, "no stream_auto_play_mode* defaults key may be written")
        XCTAssertEqual(payload(), payloadBefore, "the sync payload must keep the persisted value")

        // A profile reload (what a switch or a remote apply does) keeps the override and writes nothing.
        repository.onProfileChanged()
        XCTAssertEqual(publishedMode(), forced, "the override must survive a reload from storage")
        XCTAssertEqual(modeDefaults(), keysBefore, "a reload under the override must write nothing")
        XCTAssertEqual(payload(), payloadBefore)

        // A name that is not a mode clears it (the persisted value decides again).
        repository.setDebugStreamAutoPlayModeOverride(modeName: "NOT_A_MODE")
        XCTAssertNil(repository.currentDebugStreamAutoPlayModeOverride())
        XCTAssertEqual(publishedMode(), modeBefore, "an unknown name must leave the persisted value in charge")

        repository.setDebugStreamAutoPlayModeOverride(modeName: nil)
        XCTAssertEqual(publishedMode(), modeBefore, "clearing the override restores the persisted value")
        XCTAssertEqual(modeDefaults(), keysBefore)
        XCTAssertEqual(payload(), payloadBefore)
    }
}
