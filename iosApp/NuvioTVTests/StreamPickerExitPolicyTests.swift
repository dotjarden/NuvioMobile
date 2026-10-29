import XCTest
@testable import NuvioTV
import SharedCore

/// Batch G Wave 1 (Steven rc7): the stream picker's close-after-player rule (BUG-174, D1), its
/// loading cover (BUG-183), the shared pulse clock (BUG-182), the loading screen's one line (D2)
/// and the external-player subtitle order (D5).
@MainActor
final class StreamPickerExitPolicyTests: XCTestCase {

    // MARK: BUG-174 — what a closing player leads to

    func testEveryPlainCloseClosesThePicker() {
        XCTAssertEqual(StreamPickerExitPolicy.afterPlayerClosed(alertQueued: false, failoverPickerQueued: false,
                                                                listRequested: false), .closePicker)
    }

    func testQueuedAlertKeepsThePicker() {
        XCTAssertEqual(StreamPickerExitPolicy.afterPlayerClosed(alertQueued: true, failoverPickerQueued: false,
                                                                listRequested: false), .raiseAlert)
        // The alert wins over everything else queued.
        XCTAssertEqual(StreamPickerExitPolicy.afterPlayerClosed(alertQueued: true, failoverPickerQueued: true,
                                                                listRequested: true), .raiseAlert)
    }

    func testQueuedFailoverPickerOpensIt() {
        XCTAssertEqual(StreamPickerExitPolicy.afterPlayerClosed(alertQueued: false, failoverPickerQueued: true,
                                                                listRequested: true), .openFailoverPicker)
    }

    func testEndedWalkShowsTheList() {
        XCTAssertEqual(StreamPickerExitPolicy.afterPlayerClosed(alertQueued: false, failoverPickerQueued: false,
                                                                listRequested: true), .keepList)
    }

    // MARK: BUG-183 — the loading cover

    func testCoverIsUpFromTheFirstFrameWhenArmed() {
        // `init` armed auto mode; `onAppear` has not armed the controller yet.
        XCTAssertTrue(StreamPickerCoverPolicy.showsCover(armed: true, phase: .idle, isFailoverWalk: false, held: false))
        XCTAssertNotNil(StreamPickerCoverPolicy.message(armed: true, phase: .idle, isFailoverWalk: false))
    }

    func testNoCoverForAManualVisit() {
        XCTAssertFalse(StreamPickerCoverPolicy.showsCover(armed: false, phase: .idle, isFailoverWalk: false, held: false))
    }

    func testCoverWhileSearchingAndResolving() {
        XCTAssertTrue(StreamPickerCoverPolicy.showsCover(armed: true, phase: .searching, isFailoverWalk: false, held: false))
        XCTAssertTrue(StreamPickerCoverPolicy.showsCover(armed: true, phase: .resolving(attempt: 2),
                                                         isFailoverWalk: false, held: false))
    }

    func testDoneHidesTheCoverUnlessHeld() {
        XCTAssertFalse(StreamPickerCoverPolicy.showsCover(armed: false, phase: .done, isFailoverWalk: false, held: false))
        XCTAssertTrue(StreamPickerCoverPolicy.showsCover(armed: false, phase: .done, isFailoverWalk: false, held: true))
        // A held cover is silent: UI legs looking for "the best source" must not see it under a player.
        XCTAssertNil(StreamPickerCoverPolicy.message(armed: false, phase: .done, isFailoverWalk: false))
    }

    func testFailoverWalkResolvesBehindThePlayer() {
        XCTAssertFalse(StreamPickerCoverPolicy.showsCover(armed: false, phase: .resolving(attempt: 2),
                                                          isFailoverWalk: true, held: false))
    }

    func testGaveUpAndCancelledShowTheList() {
        for phase: FirstPlayAutoPlayController.Phase in [.exhausted, .cancelled] {
            XCTAssertFalse(StreamPickerCoverPolicy.showsCover(armed: false, phase: phase, isFailoverWalk: false, held: false))
        }
    }

    // MARK: BUG-182 — the shared pulse clock

    override func setUp() {
        super.setUp()
        PlayerLoadingPulseClock.reset()
    }

    func testSameVideoWithinGraceContinuesTheClock() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let began = PlayerLoadingPulseClock.start(for: "tt1", now: t0)
        XCTAssertEqual(began, t0)
        // The picker's cover hands over to PlayerScreen's, then the engine's, a frame or two later.
        XCTAssertEqual(PlayerLoadingPulseClock.start(for: "tt1", now: t0.addingTimeInterval(0.5)), t0)
        XCTAssertEqual(PlayerLoadingPulseClock.start(for: "tt1", now: t0.addingTimeInterval(2.4)), t0)
    }

    func testAnotherVideoRestartsTheClock() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = PlayerLoadingPulseClock.start(for: "tt1", now: t0)
        let t1 = t0.addingTimeInterval(0.2)
        XCTAssertEqual(PlayerLoadingPulseClock.start(for: "tt2", now: t1), t1)
    }

    /// Review r1 (P3): two overlays with different keys drawing at once keep their own clocks.
    func testTwoKeysOnScreenDoNotResetEachOther() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = PlayerLoadingPulseClock.start(for: "tt1", now: t0)
        _ = PlayerLoadingPulseClock.start(for: "tt2", now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(PlayerLoadingPulseClock.start(for: "tt1", now: t0.addingTimeInterval(0.2)), t0)
        XCTAssertEqual(PlayerLoadingPulseClock.start(for: "tt2", now: t0.addingTimeInterval(0.3)),
                       t0.addingTimeInterval(0.1))
    }

    func testALongPauseRestartsTheClock() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = PlayerLoadingPulseClock.start(for: "tt1", now: t0)
        let later = t0.addingTimeInterval(PlayerLoadingPulseClock.continuityGrace + 1)
        XCTAssertEqual(PlayerLoadingPulseClock.start(for: "tt1", now: later), later)
    }

    func testPulseCurve() {
        let half = PlayerLoadingOverlay.pulseSeconds
        XCTAssertEqual(PlayerLoadingPulseClock.scale(elapsed: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(PlayerLoadingPulseClock.scale(elapsed: half), PlayerLoadingOverlay.pulseScale, accuracy: 1e-9)
        XCTAssertEqual(PlayerLoadingPulseClock.scale(elapsed: half * 2), 1, accuracy: 1e-9)
        XCTAssertEqual(PlayerLoadingPulseClock.scale(elapsed: half * 3), PlayerLoadingOverlay.pulseScale, accuracy: 1e-9)
        let mid = PlayerLoadingPulseClock.scale(elapsed: half / 2)
        XCTAssertGreaterThan(mid, 1)
        XCTAssertLessThan(mid, PlayerLoadingOverlay.pulseScale)
        XCTAssertEqual(PlayerLoadingPulseClock.scale(elapsed: -1), 1)
        XCTAssertEqual(PlayerLoadingPulseClock.scale(elapsed: .nan), 1)
    }

    // MARK: D2 — the one line under the logo

    func testEpisodeLine() {
        XCTAssertEqual(PlayerLoadingOverlay.episodeLine(season: 1, episode: 4, episodeName: "Pilot"), "S1 · E4 · Pilot")
        XCTAssertEqual(PlayerLoadingOverlay.episodeLine(season: 2, episode: 10, episodeName: nil), "S2 · E10")
        XCTAssertEqual(PlayerLoadingOverlay.episodeLine(season: 2, episode: 10, episodeName: ""), "S2 · E10")
    }

    func testMoviesHaveNoLine() {
        XCTAssertNil(PlayerLoadingOverlay.episodeLine(season: nil, episode: nil, episodes: []))
        XCTAssertNil(PlayerLoadingOverlay.episodeLine(season: 1, episode: nil, episodes: []))
    }

    // MARK: D5 — external-player subtitles

    private typealias Item = ExternalSubtitleHandOff.Item

    private func item(_ url: String, _ lang: String) -> Item { Item(url: url, name: lang, lang: lang) }

    /// Primary-subtag match, the shape of the shared `languageMatchesPreference`.
    private let matches: (String, String) -> Bool = { track, target in
        track.lowercased().split(separator: "-").first == target.lowercased().split(separator: "-").first
    }

    func testStreamSubtitlesFirstThenPreferredLanguage() {
        let own = [item("https://s/own.srt", "en")]
        let addon = [item("https://a/1.srt", "de"), item("https://a/2.srt", "fr"),
                     item("https://a/3.srt", "fr-CA"), item("https://a/4.srt", "en")]
        let out = ExternalSubtitleHandOff.merge(own: own, addon: addon, preferredTargets: ["fr", "en"], matches: matches)
        XCTAssertEqual(out.map(\.url), ["https://s/own.srt", "https://a/2.srt", "https://a/3.srt",
                                        "https://a/4.srt", "https://a/1.srt"])
    }

    func testNoPreferenceKeepsTheRepositoryOrder() {
        let addon = [item("https://a/1.srt", "de"), item("https://a/2.srt", "fr")]
        let out = ExternalSubtitleHandOff.merge(own: [], addon: addon, preferredTargets: [], matches: matches)
        XCTAssertEqual(out.map(\.url), ["https://a/1.srt", "https://a/2.srt"])
    }

    func testDuplicateURLsAreSentOnce() {
        let own = [item("https://s/x.srt", "en")]
        let addon = [item("https://s/x.srt", "en"), item(" https://s/x.srt ", "en"), item("", "en"),
                     item("https://a/y.srt", "en")]
        let out = ExternalSubtitleHandOff.merge(own: own, addon: addon, preferredTargets: ["en"], matches: matches)
        XCTAssertEqual(out.map(\.url), ["https://s/x.srt", "https://a/y.srt"])
    }

    func testCapKeepsTheStreamsOwnAndTheBestAddonOnes() {
        let own = [item("https://s/own.srt", "en")]
        let addon = (1...20).map { item("https://a/\($0).srt", $0 == 20 ? "fr" : "de") }
        let out = ExternalSubtitleHandOff.merge(own: own, addon: addon, preferredTargets: ["fr"], matches: matches)
        XCTAssertEqual(out.count, ExternalSubtitleHandOff.cap)
        XCTAssertEqual(out.first?.url, "https://s/own.srt")
        XCTAssertEqual(out[1].url, "https://a/20.srt", "the preferred-language add-on subtitle survives the cap")
    }
}
