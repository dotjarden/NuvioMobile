import XCTest
@testable import NuvioTV

/// Unit tests for `PlayerAudioLanguagePlan` (`Screens/Player/PlayerAudioLanguagePlan.swift`) — the
/// pure mpv `alang`/force-track decision logic backing upstream 4f79bfe0's proactive audio-language
/// preference. Covers the priority-order walk over `trackToForce` and the comma-join in
/// `alangValue`. No mpv/UIKit dependency, so these run as plain XCTest against the real app target
/// via `@testable import NuvioTV`, matching `SubtitleVTTShiftTests`.
final class PlayerAudioLanguagePlanTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTracks(_ tracks: (id: Int, lang: String, selected: Bool)...) -> [(id: Int, lang: String, selected: Bool)] {
        tracks
    }

    // MARK: - alangValue

    func testAlangValueJoinsTargetsInOrder() {
        XCTAssertEqual(PlayerAudioLanguagePlan.alangValue(targets: ["ja", "en"]), "ja,en")
        XCTAssertEqual(PlayerAudioLanguagePlan.alangValue(targets: []), "")
    }

    // MARK: - trackToForce

    func testEmptyTargetsForcesNothing() {
        let tracks = makeTracks((id: 1, lang: "en", selected: false))
        XCTAssertNil(PlayerAudioLanguagePlan.trackToForce(targets: [], tracks: tracks))
    }

    func testNoMatchingTrackLeavesDefault() {
        let tracks = makeTracks(
            (id: 1, lang: "en", selected: true),
            (id: 2, lang: "fr", selected: false)
        )
        XCTAssertNil(PlayerAudioLanguagePlan.trackToForce(targets: ["ja"], tracks: tracks))
    }

    func testAlreadySelectedMatchDoesNotRepoke() {
        let tracks = makeTracks(
            (id: 1, lang: "en", selected: false),
            (id: 2, lang: "ja", selected: true)
        )
        XCTAssertNil(PlayerAudioLanguagePlan.trackToForce(targets: ["ja"], tracks: tracks))
    }

    func testUnselectedMatchIsForced() {
        let tracks = makeTracks(
            (id: 1, lang: "en", selected: true),
            (id: 2, lang: "ja", selected: false),
            (id: 3, lang: "ja", selected: false)
        )
        XCTAssertEqual(PlayerAudioLanguagePlan.trackToForce(targets: ["ja"], tracks: tracks), 2)
    }

    func testSecondaryTargetOnlyWhenPrimaryHasNoHit() {
        let noPrimaryHit = makeTracks(
            (id: 1, lang: "en", selected: true),
            (id: 2, lang: "de", selected: false)
        )
        XCTAssertEqual(PlayerAudioLanguagePlan.trackToForce(targets: ["ja", "de"], tracks: noPrimaryHit), 2)

        // Primary target wins even though the secondary target's track is already selected —
        // the walk stops at the first target with any match, it never looks past it.
        let primaryHitButUnselected = makeTracks(
            (id: 1, lang: "ja", selected: false),
            (id: 2, lang: "de", selected: true)
        )
        XCTAssertEqual(PlayerAudioLanguagePlan.trackToForce(targets: ["ja", "de"], tracks: primaryHitButUnselected), 1)
    }

    func testIso6392TrackMatchesIso6391Target() {
        // "eng"/"jpn" are ISO-639-2 codes; `languageMatchesPreference` normalizes both to
        // ISO-639-1 ("en"/"ja") via `LanguageCodeAliases` before comparing.
        let tracks = makeTracks(
            (id: 1, lang: "eng", selected: true),
            (id: 2, lang: "jpn", selected: false)
        )
        XCTAssertEqual(PlayerAudioLanguagePlan.trackToForce(targets: ["ja"], tracks: tracks), 2)
    }

    func testRegionalTrackMatchesBaseTarget() {
        // "pt-BR" normalizes to "pt-br"; matching against target "pt" falls through to the
        // primary-subtag comparison ("pt" == "pt") since the full codes differ.
        let tracks = makeTracks(
            (id: 1, lang: "en", selected: true),
            (id: 2, lang: "pt-BR", selected: false)
        )
        XCTAssertEqual(PlayerAudioLanguagePlan.trackToForce(targets: ["pt"], tracks: tracks), 2)
    }
}
