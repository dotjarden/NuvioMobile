import XCTest
@testable import NuvioTV
import SharedCore

/// Unit tests for the up-next trigger in `Screens/NextEpisodeAutoPlay.swift`: the threshold math
/// (`NextEpisodeTriggerPolicy`, unchanged from the inline version), the FEAT-49 Tier 1 preload
/// (upstream 22c9ab20) through the engine's `Hooks.loadStreams` seam, and the #2150 end-of-file
/// re-arm decision. The engine is driven with `configureForTesting`, so no SharedCore singleton
/// (settings, streams, shuffle) is touched; `settings` stays nil, so `beginSearch()` returns right
/// after the `Hooks.searchBegan` signal.
@MainActor
final class NextEpisodeEngineTests: XCTestCase {

    private static let duration: Double = 2400
    private static let slack: Double = 1.5

    // MARK: - Fixtures

    private struct LoadCall: Equatable {
        let type: String
        let videoId: String
        let season: Int?
        let episode: Int?
    }

    private final class Recorder {
        var calls: [LoadCall] = []
        var searchBegan = 0
    }

    private func makeContext() -> PlaybackContext {
        PlaybackContext(
            url: URL(string: "https://cdn.example.com/s1e1.mkv")!, title: "S1E1", contentType: "series",
            parentMetaId: "tt1", videoId: "tt1:1:1",
            season: 1, episode: 1, poster: nil, background: nil, providerName: nil, providerAddonId: nil,
            streamTitle: nil, streamSubtitle: nil, externalSubtitles: []
        )
    }

    private func episode(season: Int32, episode: Int32) -> MetaVideo {
        MetaVideo(
            id: "tt1:\(season):\(episode)", title: "Episode \(episode)", released: nil, available: true,
            thumbnail: nil, seasonPoster: nil,
            season: KotlinInt(int: season), episode: KotlinInt(int: episode),
            overview: nil, runtime: nil, rating: nil, streams: []
        )
    }

    private func trigger(percentageMode: Bool = true, percent: Double = 99, minutes: Double = 2,
                         timeout: Int = 3, preload: Bool = false) -> NextEpisodeEngine.TriggerSettings {
        NextEpisodeEngine.TriggerSettings(
            percentageMode: percentageMode,
            thresholdPercent: percent,
            thresholdMinutesBeforeEnd: minutes,
            autoPlayTimeoutSeconds: timeout,
            preloadEnabled: preload
        )
    }

    private func stream(url: String? = nil, ytId: String? = nil, infoHash: String? = nil) -> StreamItem {
        StreamItem(
            name: "1080p", title: nil, description: nil, url: url, infoHash: infoHash, fileIdx: nil,
            externalUrl: nil, ytId: ytId, sources: [], sourceName: nil, addonName: "Add-on", addonId: "addon:x",
            addonLogo: nil, streamType: nil,
            behaviorHints: StreamBehaviorHints(bingeGroup: nil, notWebReady: false, videoHash: nil, videoSize: nil,
                                               filename: nil, proxyHeaders: nil),
            clientResolve: nil, debridCacheStatus: nil, externalSubtitles: [], badges: []
        )
    }

    // MARK: - Source predicates (batch D U2)

    func testYouTubeOnlyStreamIsListableButNeverAnAutoPlayCandidate() {
        // The debrid half is injected as "never" so no debrid settings are read.
        let never: (StreamItem) -> Bool = { _ in false }
        let yt = stream(ytId: "dQw4w9WgXcQ")
        XCTAssertFalse(NextEpisodeEngine.isAutoPlayCandidate(yt, resolvesThroughDebrid: never),
                       "auto-play never spends seconds resolving a YouTube video")
        XCTAssertTrue(NextEpisodeEngine.isListable(yt, resolvesThroughDebrid: never),
                      "the viewer may still pick it from the in-player source list")

        let direct = stream(url: "https://cdn.example.com/s1e2.mkv")
        XCTAssertTrue(NextEpisodeEngine.isAutoPlayCandidate(direct, resolvesThroughDebrid: never))
        XCTAssertTrue(NextEpisodeEngine.isListable(direct, resolvesThroughDebrid: never))

        let torrent = stream(infoHash: "feedface")
        XCTAssertFalse(NextEpisodeEngine.isAutoPlayCandidate(torrent, resolvesThroughDebrid: never))
        XCTAssertFalse(NextEpisodeEngine.isListable(torrent, resolvesThroughDebrid: never),
                       "a torrent with no debrid connection is neither")
        XCTAssertTrue(NextEpisodeEngine.isAutoPlayCandidate(torrent, resolvesThroughDebrid: { _ in true }))
        XCTAssertTrue(NextEpisodeEngine.isListable(torrent, resolvesThroughDebrid: { _ in true }))
    }

    private func makeEngine(trigger: NextEpisodeEngine.TriggerSettings, recorder: Recorder) -> NextEpisodeEngine {
        let hooks = NextEpisodeEngine.Hooks(loadStreams: { type, videoId, season, episode in
            recorder.calls.append(LoadCall(type: type, videoId: videoId, season: season?.value, episode: episode?.value))
        }, searchBegan: { recorder.searchBegan += 1 })
        let engine = NextEpisodeEngine(context: makeContext(), onPlayNext: { _ in }, hooks: hooks)
        engine.configureForTesting(nextVideo: episode(season: 1, episode: 2), trigger: trigger)
        return engine
    }

    private func reaches(_ position: Double, _ trigger: NextEpisodeEngine.TriggerSettings,
                         hold: Double? = nil, duration: Double = NextEpisodeEngineTests.duration) -> Bool {
        NextEpisodeTriggerPolicy.reachesThreshold(
            positionSec: position, durationSec: duration, trigger: trigger,
            holdUntilSec: hold, endOfFileSlack: Self.slack
        )
    }

    // MARK: - Policy: percentage

    func testNinetyNinePercentOf2400FiresAt2376Not2375() {
        let t = trigger(percent: 99)
        XCTAssertFalse(reaches(2375, t))
        XCTAssertTrue(reaches(2376, t))
    }

    func testPercentBelow97ClampsTo97() {
        let t = trigger(percent: 50)
        XCTAssertFalse(reaches(1200, t))
        XCTAssertFalse(reaches(2327, t))   // 96.96 %
        XCTAssertTrue(reaches(2328, t))    // 97 %
    }

    func testHundredPercentFiresOnlyAtTheEnd() {
        let t = trigger(percent: 100)
        XCTAssertFalse(reaches(2399, t))
        XCTAssertTrue(reaches(2400, t))
    }

    // MARK: - Policy: minutes before end

    func testTwoMinutesFiresAtDurationMinus120() {
        let t = trigger(percentageMode: false, minutes: 2)
        XCTAssertFalse(reaches(2279, t))
        XCTAssertTrue(reaches(2280, t))
    }

    func testTenMinutesClampsToThreeAndAHalf() {
        let t = trigger(percentageMode: false, minutes: 10)
        XCTAssertFalse(reaches(2189, t))
        XCTAssertTrue(reaches(2190, t))    // D − 210
    }

    func testZeroMinutesFiresAtTheEnd() {
        let t = trigger(percentageMode: false, minutes: 0)
        XCTAssertFalse(reaches(2399.9, t))
        XCTAssertTrue(reaches(2400, t))
    }

    // MARK: - Policy: post-credits hold

    func testHoldReplacesTheThreshold() {
        let t = trigger(percent: 99)       // would fire at 2376 without a hold
        XCTAssertFalse(reaches(2380, t, hold: 2390))
        XCTAssertTrue(reaches(2390, t, hold: 2390))
    }

    func testEndOfFileSlackFiresEvenWithAHoldBeyondTheEnd() {
        let t = trigger(percent: 99)
        XCTAssertFalse(reaches(2398.4, t, hold: 2500))
        XCTAssertTrue(reaches(2398.5, t, hold: 2500))   // D − 1.5
    }

    // MARK: - Policy: preload lead

    func testPreloadLeadIsTheTimeoutFlooredAtThirtySeconds() {
        XCTAssertEqual(NextEpisodeTriggerPolicy.preloadLeadSeconds(timeoutSeconds: 3), 30)
        XCTAssertEqual(NextEpisodeTriggerPolicy.preloadLeadSeconds(timeoutSeconds: 30), 30)
        XCTAssertEqual(NextEpisodeTriggerPolicy.preloadLeadSeconds(timeoutSeconds: 45), 45)
    }

    // MARK: - Engine: preload ticks

    func testPreloadOnIssuesOneSilentLoadThirtySecondsAhead() {
        let recorder = Recorder()
        let engine = makeEngine(trigger: trigger(percent: 99, preload: true), recorder: recorder)

        engine.onProgress(positionSec: 2340, durationSec: Self.duration)
        XCTAssertTrue(recorder.calls.isEmpty)

        engine.onProgress(positionSec: 2346, durationSec: Self.duration)
        XCTAssertEqual(recorder.calls, [LoadCall(type: "series", videoId: "tt1:1:2", season: 1, episode: 2)])
        XCTAssertEqual(engine.phase, .hidden)

        engine.onProgress(positionSec: 2350, durationSec: Self.duration)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(engine.phase, .hidden)
    }

    func testCancelInsideTheLeadWindowIsANoOpAndDoesNotReissue() {
        let recorder = Recorder()
        let engine = makeEngine(trigger: trigger(percent: 99, preload: true), recorder: recorder)

        engine.onProgress(positionSec: 2346, durationSec: Self.duration)
        XCTAssertEqual(recorder.calls.count, 1)

        engine.cancel()                     // a backward seek before the card: nothing to cancel
        XCTAssertEqual(engine.phase, .hidden)

        engine.onProgress(positionSec: 2360, durationSec: Self.duration)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(engine.phase, .hidden)
    }

    func testPreloadOffIssuesNothingBeforeTheThreshold() {
        let recorder = Recorder()
        let engine = makeEngine(trigger: trigger(percent: 99, preload: false), recorder: recorder)

        for position in [2340.0, 2346, 2350, 2360, 2375] {
            engine.onProgress(positionSec: position, durationSec: Self.duration)
        }
        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertEqual(engine.phase, .hidden)
    }

    func testMinutesModePreloadFiresAtThresholdMinusLead() {
        let recorder = Recorder()
        let engine = makeEngine(trigger: trigger(percentageMode: false, minutes: 2, preload: true), recorder: recorder)

        engine.onProgress(positionSec: 2249, durationSec: Self.duration)
        XCTAssertTrue(recorder.calls.isEmpty)

        engine.onProgress(positionSec: 2250, durationSec: Self.duration)   // D − 150
        XCTAssertEqual(recorder.calls, [LoadCall(type: "series", videoId: "tt1:1:2", season: 1, episode: 2)])
        XCTAssertEqual(engine.phase, .hidden)
    }

    // MARK: - Engine: search trigger and #2150 rider
    //
    // `settings` is nil in tests, so `beginSearch()` returns right after `searchBegan`; phase stays
    // `.hidden`, which is why the dismissal is simulated (`simulateDismissForTesting`) instead of
    // calling `dismissIfVisible()`. Not exercised here: the `preloaded` reset after teardown, the
    // resolve-race guard (both need a live search / debrid resolve, i.e. SharedCore singletons), and
    // the `dismissIfVisible` phase switch (fix #3: `.noStream`/`.stillWatching` never arm the re-arm;
    // `.searching`/`.counting` arm it only when not at end of file), which
    // `simulateDismissForTesting()` bypasses.

    func testNoSearchBeforeTheThresholdThenOneAtIt() {
        let recorder = Recorder()
        let engine = makeEngine(trigger: trigger(percent: 99), recorder: recorder)

        for position in [2000.0, 2350, 2375] {
            engine.onProgress(positionSec: position, durationSec: Self.duration)
        }
        XCTAssertEqual(recorder.searchBegan, 0)

        engine.onProgress(positionSec: 2376, durationSec: Self.duration)
        XCTAssertEqual(recorder.searchBegan, 1)
        engine.onProgress(positionSec: 2377, durationSec: Self.duration)
        XCTAssertEqual(recorder.searchBegan, 1)
    }

    func testDismissedCardRearmsOnceAtEndOfFileThenSticks() {
        let recorder = Recorder()
        let engine = makeEngine(trigger: trigger(percent: 99), recorder: recorder)

        engine.onProgress(positionSec: 2380, durationSec: Self.duration)
        XCTAssertEqual(recorder.searchBegan, 1)

        engine.simulateDismissForTesting()
        engine.onProgress(positionSec: 2390, durationSec: Self.duration)     // dismissed, not at EOF
        XCTAssertEqual(recorder.searchBegan, 1)

        engine.onProgress(positionSec: 2398.5, durationSec: Self.duration)   // D - 1.5: re-arm
        XCTAssertEqual(recorder.searchBegan, 2)
        engine.onProgress(positionSec: 2399, durationSec: Self.duration)
        XCTAssertEqual(recorder.searchBegan, 2)

        engine.simulateDismissForTesting()                                   // second dismissal sticks
        engine.onProgress(positionSec: 2399.5, durationSec: Self.duration)
        XCTAssertEqual(recorder.searchBegan, 2)
    }

    // MARK: - #2150 rider policy

    func testRearmTruthTable() {
        func rearm(_ position: Double, dismissed: Bool, rearmed: Bool, duration: Double = Self.duration) -> Bool {
            NextEpisodeTriggerPolicy.shouldRearmAfterDismiss(
                positionSec: position, durationSec: duration,
                dismissedByUser: dismissed, alreadyRearmed: rearmed, endOfFileSlack: Self.slack
            )
        }
        // Dismissed by the user, first time, at the end → re-arm.
        XCTAssertTrue(rearm(2400, dismissed: true, rearmed: false))
        XCTAssertTrue(rearm(2398.5, dismissed: true, rearmed: false))
        // Not yet at the end.
        XCTAssertFalse(rearm(2398.4, dismissed: true, rearmed: false))
        XCTAssertFalse(rearm(2000, dismissed: true, rearmed: false))
        // A seek/exit cancel (not a dismissal) never re-arms.
        XCTAssertFalse(rearm(2400, dismissed: false, rearmed: false))
        // Once per session.
        XCTAssertFalse(rearm(2400, dismissed: true, rearmed: true))
        // No duration yet.
        XCTAssertFalse(rearm(0, dismissed: true, rearmed: false, duration: 0))
    }
}
