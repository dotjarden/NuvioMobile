import XCTest
@testable import NuvioTV

/// B10 (BUG-166; Steven, beta.19-rc4 verdict 2026-10-16, "DV colours wrong"): a Dolby Vision
/// profile 5 stream the router sends to mpv asks for `gpu-next` (mpv's `gpu` VO has no RPU
/// processing); every other decision leaves the renderer to the setting.
final class PlayerEngineRouterTests: XCTestCase {

    private let mp4 = "mov,mp4,m4a,3gp,3g2,mj2"

    private func sample(dv: DolbyVisionInfo?, container: String = "matroska,webm",
                        videoStreams: Int = 1, audio: [String] = ["eac3"]) -> ProbeResult {
        ProbeResult(
            container: container, videoCodec: "hevc", videoProfile: 0, hdr: .sdr, dolbyVision: dv,
            audio: audio.enumerated().map { AudioStreamInfo(index: $0.offset, codec: $0.element, channels: 6, language: "eng") },
            subtitles: [], durationSec: 3600, seekable: true, videoStreamCount: videoStreams
        )
    }

    private let p5 = DolbyVisionInfo(profile: 5, level: 6, blPresent: true, elPresent: false, rpuPresent: true, compatId: 0)
    private let p81 = DolbyVisionInfo(profile: 8, level: 6, blPresent: true, elPresent: false, rpuPresent: true, compatId: 1)
    private let p7 = DolbyVisionInfo(profile: 7, level: 6, blPresent: true, elPresent: true, rpuPresent: true,
                                     compatId: 0, elKind: .mel)

    func testP5InMP4GoesToMpvOnGpuNext() {
        let decision = PlayerEngineRouter.route(probe: sample(dv: p5, container: mp4), nativeDVEnabled: true)
        XCTAssertEqual(decision.engine, .mpv)
        XCTAssertTrue(decision.prefersGpuNext)
        XCTAssertTrue(decision.displayNote.hasSuffix("\u{00B7} gpu-next"), decision.displayNote)
    }

    func testP5OnMpvForAnotherReasonStillGetsGpuNext() {
        let decision = PlayerEngineRouter.route(probe: sample(dv: p5, audio: ["opus"]), nativeDVEnabled: true)
        XCTAssertEqual(decision.engine, .mpv)
        XCTAssertTrue(decision.prefersGpuNext)
    }

    func testP5InMatroskaStaysNativeWithoutTheFlag() {
        let decision = PlayerEngineRouter.route(probe: sample(dv: p5), nativeDVEnabled: true)
        XCTAssertEqual(decision.engine, .native)
        XCTAssertFalse(decision.prefersGpuNext)
    }

    func testP8NativeAndP7TwoTrackDoNotForceGpuNext() {
        let p8 = PlayerEngineRouter.route(probe: sample(dv: p81, container: mp4), nativeDVEnabled: true)
        XCTAssertEqual(p8.engine, .native)
        XCTAssertFalse(p8.prefersGpuNext)
        let twoTrack = PlayerEngineRouter.route(probe: sample(dv: p7, videoStreams: 2), nativeDVEnabled: true)
        XCTAssertEqual(twoTrack.engine, .mpv)
        XCTAssertFalse(twoTrack.prefersGpuNext)
        XCTAssertFalse(twoTrack.displayNote.contains("gpu-next"))
    }

    func testFallbackRuleReadsTheProbe() {
        XCTAssertTrue(PlayerEngineRouter.mpvNeedsGpuNext(probe: sample(dv: p5)))
        XCTAssertFalse(PlayerEngineRouter.mpvNeedsGpuNext(probe: sample(dv: p81)))
        XCTAssertFalse(PlayerEngineRouter.mpvNeedsGpuNext(probe: sample(dv: nil)))
        XCTAssertFalse(PlayerEngineRouter.mpvNeedsGpuNext(probe: nil))
    }
}
