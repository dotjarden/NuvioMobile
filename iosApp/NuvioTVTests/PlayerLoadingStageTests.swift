import XCTest
@testable import NuvioTV

/// P4 B24 (spec §8.1–8.2, §10.1): the loading screen's status copy and the mpv startup reducer.
final class PlayerLoadingStageTests: XCTestCase {

    // MARK: Status text

    func testStatusTextForEveryStage() {
        XCTAssertEqual(PlayerLoadingStage.checking.statusText, "Checking the stream\u{2026}")
        XCTAssertEqual(PlayerLoadingStage.connecting.statusText, "Connecting\u{2026}")
        XCTAssertEqual(PlayerLoadingStage.preparing(dolbyVision: false).statusText, "Preparing playback\u{2026}")
        XCTAssertEqual(PlayerLoadingStage.preparing(dolbyVision: true).statusText, "Preparing Dolby Vision\u{2026}")
        XCTAssertEqual(PlayerLoadingStage.subtitles.statusText, "Loading subtitles\u{2026}")
        XCTAssertEqual(PlayerLoadingStage.buffering(percent: nil).statusText, "Buffering\u{2026}")
        XCTAssertEqual(PlayerLoadingStage.buffering(percent: 42).statusText, "Buffering 42 %")
        XCTAssertEqual(PlayerLoadingStage.started.statusText, "")
    }

    /// The preparing copy is the native caption's own strings (`NativePreparingLabel`), reused.
    func testPreparingTextMatchesTheNativeCaption() {
        XCTAssertEqual(PlayerLoadingStage.preparing(dolbyVision: false).statusText, NativePreparingLabel.text(for: nil))
    }

    func testDebugNames() {
        XCTAssertEqual(PlayerLoadingStage.preparing(dolbyVision: true).debugName, "preparing(dv)")
        XCTAssertEqual(PlayerLoadingStage.buffering(percent: 7).debugName, "buffering(7)")
        XCTAssertTrue(PlayerLoadingStage.started.isStarted)
        XCTAssertFalse(PlayerLoadingStage.buffering(percent: nil).isStarted)
    }

    // MARK: mpv reducer

    func testStartsConnecting() {
        let r = MPVStartupStageReducer()
        XCTAssertEqual(r.stage, .connecting)
        XCTAssertFalse(r.started)
    }

    func testFileLoadedMovesToBuffering() {
        var r = MPVStartupStageReducer()
        XCTAssertTrue(r.fileLoaded(resumeGeneration: nil))
        XCTAssertEqual(r.stage, .buffering(percent: nil))
    }

    func testRestartBeforeFileLoadedIsIgnored() {
        var r = MPVStartupStageReducer()
        XCTAssertFalse(r.playbackRestart(completesSeek: nil))
        XCTAssertEqual(r.stage, .connecting)
    }

    func testNoResumeSeekAnyRestartStarts() {
        var r = MPVStartupStageReducer()
        r.fileLoaded(resumeGeneration: nil)
        XCTAssertTrue(r.playbackRestart(completesSeek: nil))
        XCTAssertEqual(r.stage, .started)
    }

    func testRestartBeforeTheResumeSeekDoesNotStart() {
        var r = MPVStartupStageReducer()
        r.fileLoaded(resumeGeneration: 3)
        XCTAssertFalse(r.playbackRestart(completesSeek: nil), "mpv's own start-of-playback restart")
        XCTAssertFalse(r.playbackRestart(completesSeek: 2), "an older seek's completion")
        XCTAssertEqual(r.stage, .buffering(percent: nil))
        XCTAssertTrue(r.playbackRestart(completesSeek: 3), "the resume seek's completion")
        XCTAssertEqual(r.stage, .started)
    }

    func testBufferingPercent() {
        var r = MPVStartupStageReducer()
        XCTAssertFalse(r.bufferingPercent(10), "no percentage while connecting")
        r.fileLoaded(resumeGeneration: nil)
        XCTAssertTrue(r.bufferingPercent(42))
        XCTAssertEqual(r.stage, .buffering(percent: 42))
        XCTAssertFalse(r.bufferingPercent(42), "same value, no change")
        r.bufferingPercent(140)
        XCTAssertEqual(r.stage, .buffering(percent: 100))
    }

    func testPositionAdvanceBackstop() {
        var r = MPVStartupStageReducer()
        r.fileLoaded(resumeGeneration: 9)            // a resume seek whose restart never comes
        XCTAssertFalse(r.tick(positionSec: 100, paused: false))   // baseline
        XCTAssertFalse(r.tick(positionSec: 100.8, paused: false))
        XCTAssertFalse(r.tick(positionSec: 105, paused: true), "paused: no advance counted")
        XCTAssertFalse(r.tick(positionSec: 105, paused: false))   // new baseline after the pause
        XCTAssertTrue(r.tick(positionSec: 106.2, paused: false))
        XCTAssertEqual(r.stage, .started)
    }

    func testStartedNeverMovesBack() {
        var r = MPVStartupStageReducer()
        r.fileLoaded(resumeGeneration: nil)
        r.playbackRestart(completesSeek: nil)
        XCTAssertFalse(r.bufferingPercent(5), "a mid-play rebuffer is not a startup stage")
        XCTAssertFalse(r.fileLoaded(resumeGeneration: nil))
        XCTAssertFalse(r.playbackRestart(completesSeek: 4))
        XCTAssertEqual(r.stage, .started)
    }
}
