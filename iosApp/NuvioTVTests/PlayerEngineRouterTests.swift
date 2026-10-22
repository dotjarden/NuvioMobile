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

    /// P5 spike (2026-10-20): the P3-F7 rule is gone; P5 in MP4 routes native like P5 in Matroska.
    func testP5InMP4RoutesNative() {
        let decision = PlayerEngineRouter.route(probe: sample(dv: p5, container: mp4), nativeDVEnabled: true)
        XCTAssertEqual(decision.engine, .native)
        XCTAssertFalse(decision.prefersGpuNext)
        XCTAssertFalse(decision.displayNote.contains("gpu-next"), decision.displayNote)
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

    // P5 spike (2026-10-20): the remux treats an hvcC with no parameter-set arrays like missing
    // extradata (the in-band `dvhe` layout of DV P5 WEB-DL MP4s: init.mp4 shipped a 31-byte hvcC,
    // numArrays=0, and AVPlayer failed the item with CoreMediaErrorDomain -4).
    func testHvccWithNoArraysLacksParameterSets() {
        var hvcc = [UInt8](repeating: 0, count: 23); hvcc[0] = 1; hvcc[21] = 0x0F; hvcc[22] = 0
        hvcc.withUnsafeBufferPointer { XCTAssertTrue(RemuxSession.hvccHasNoParameterSets($0)) }
    }

    func testHvccWithEmptyArraysLacksParameterSets() {
        var hvcc = [UInt8](repeating: 0, count: 23); hvcc[0] = 1; hvcc[22] = 2
        hvcc += [0xA0, 0, 0]            // VPS array, numNalus = 0
        hvcc += [0xA1, 0, 0]            // SPS array, numNalus = 0
        hvcc.withUnsafeBufferPointer { XCTAssertTrue(RemuxSession.hvccHasNoParameterSets($0)) }
    }

    func testHvccWithParameterSetsIsComplete() {
        var hvcc = [UInt8](repeating: 0, count: 23); hvcc[0] = 1; hvcc[22] = 1
        hvcc += [0xA1, 0, 1, 0, 2, 0x42, 0x01]   // one SPS NAL of 2 bytes
        hvcc.withUnsafeBufferPointer { XCTAssertFalse(RemuxSession.hvccHasNoParameterSets($0)) }
    }

    func testAnnexBAndShortExtradataAreNotTreatedAsEmptyHvcc() {
        let annexB: [UInt8] = [0, 0, 0, 1, 0x40, 0x01, 0x0C] + [UInt8](repeating: 0, count: 20)
        annexB.withUnsafeBufferPointer { XCTAssertFalse(RemuxSession.hvccHasNoParameterSets($0)) }
        let short: [UInt8] = [1, 2, 3]
        short.withUnsafeBufferPointer { XCTAssertFalse(RemuxSession.hvccHasNoParameterSets($0)) }
    }

    // P5 Wave 3: the native signaling retry only when there is a SUPPLEMENTAL-CODECS to drop.
    func testSignalingRetryOnlyWhenSupplementalCodecsExist() {
        XCTAssertTrue(NativePlaybackCoordinator.signalingRetryAllowed(attempt: 0, supplementalCodecs: "dvh1.08.06/db1p"))
        XCTAssertFalse(NativePlaybackCoordinator.signalingRetryAllowed(attempt: 0, supplementalCodecs: nil))
        XCTAssertFalse(NativePlaybackCoordinator.signalingRetryAllowed(attempt: 0, supplementalCodecs: ""))
        XCTAssertFalse(NativePlaybackCoordinator.signalingRetryAllowed(attempt: 1, supplementalCodecs: "dvh1.08.06/db1p"))
    }

    func testFallbackRuleReadsTheProbe() {
        XCTAssertTrue(PlayerEngineRouter.mpvNeedsGpuNext(probe: sample(dv: p5)))
        XCTAssertFalse(PlayerEngineRouter.mpvNeedsGpuNext(probe: sample(dv: p81)))
        XCTAssertFalse(PlayerEngineRouter.mpvNeedsGpuNext(probe: sample(dv: nil)))
        XCTAssertFalse(PlayerEngineRouter.mpvNeedsGpuNext(probe: nil))
    }

    // MARK: - W3-19 (wave3c review r1 P3-2 / r2 P3-2): the `[PlayerRouter]` probe lines' pure parts

    /// The probe "ran out the clock" when it finished within 50 ms of the cap; anything quicker
    /// failed early (unreachable, unreadable).
    func testProbeOutcomeSplitsACapHitFromAnEarlyFailureAtFiftyMsBelowTheCap() {
        XCTAssertEqual(PlayerRouterLog.probeOutcome(ms: 3949, capMs: 4000), "probe failed early")
        XCTAssertEqual(PlayerRouterLog.probeOutcome(ms: 3950, capMs: 4000), "probe cap hit")
        XCTAssertEqual(PlayerRouterLog.probeOutcome(ms: 4000, capMs: 4000), "probe cap hit")
        XCTAssertEqual(PlayerRouterLog.probeOutcome(ms: 4210, capMs: 4000), "probe cap hit")
        XCTAssertEqual(PlayerRouterLog.probeOutcome(ms: 0, capMs: 4000), "probe failed early")
    }

    /// The privacy guard: Release prints the top-level domain only, so a self-hosted add-on, proxy
    /// or home-server host never reaches a rig console log (the rig logs fall under the staging rule).
    func testHostIsRedactedToItsTopLevelDomain() throws {
        func redacted(_ string: String) throws -> String {
            PlayerRouterLog.host(try XCTUnwrap(URL(string: string), string), reveal: false)
        }
        XCTAssertEqual(try redacted("https://a.b.example.com/x"), "<redacted>.com")
        XCTAssertEqual(try redacted("https://example.org:8443/stream.mkv?token=abc"), "<redacted>.org")
        XCTAssertEqual(try redacted("https://media.home-server.example.co.uk/v"), "<redacted>.uk")
    }

    /// An IP literal or a dotless name says nothing a log should keep, and has no top-level domain
    /// to show; a trailing dot has none either.
    func testHostIsFullyRedactedForAnIPLiteralADotlessNameAndATrailingDot() throws {
        func redacted(_ string: String) throws -> String {
            PlayerRouterLog.host(try XCTUnwrap(URL(string: string), string), reveal: false)
        }
        XCTAssertEqual(try redacted("http://192.168.1.10:8080/"), "<redacted>")
        XCTAssertEqual(try redacted("http://10.0.0.2/x.mkv"), "<redacted>")
        XCTAssertEqual(try redacted("http://[fe80::1]/"), "<redacted>")
        XCTAssertEqual(try redacted("http://[2001:db8::7]:8096/"), "<redacted>")
        XCTAssertEqual(try redacted("http://nas/"), "<redacted>")
        XCTAssertEqual(try redacted("http://localhost:32400/"), "<redacted>")
        XCTAssertEqual(try redacted("http://example.com./"), "<redacted>")
    }

    /// The reveal path (DEBUG builds, or `-debug.playerRouterHosts YES` in Release) prints the host
    /// whole, IP literals and dotless names included.
    func testHostIsFullWhenRevealed() throws {
        func revealed(_ string: String) throws -> String {
            PlayerRouterLog.host(try XCTUnwrap(URL(string: string), string), reveal: true)
        }
        XCTAssertEqual(try revealed("https://a.b.example.com/x"), "a.b.example.com")
        XCTAssertEqual(try revealed("http://192.168.1.10:8080/"), "192.168.1.10")
        XCTAssertEqual(try revealed("http://nas/"), "nas")
        XCTAssertEqual(PlayerRouterLog.revealHostsKey, "debug.playerRouterHosts")
        #if DEBUG
        XCTAssertTrue(PlayerRouterLog.revealsHosts, "DEBUG builds always print the host")
        XCTAssertEqual(PlayerRouterLog.host(try XCTUnwrap(URL(string: "https://a.b.example.com/x"))),
                       "a.b.example.com", "the default argument is the latched reveal setting")
        #endif
    }

    /// A URL with no host prints `-`, revealed or not.
    func testHostIsADashWhenTheURLHasNone() throws {
        let file = try XCTUnwrap(URL(string: "file:///tmp/x.mkv"))
        XCTAssertEqual(PlayerRouterLog.host(file, reveal: false), "-")
        XCTAssertEqual(PlayerRouterLog.host(file, reveal: true), "-")
    }
}
