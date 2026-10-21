import XCTest
@testable import NuvioTV

/// BUG-199b: the reposition scan and the copy-loop cut compare packets in the keyframe INDEX's
/// timestamp domain. mov indexes the sample DTS (mov.c: `e->timestamp = current_dts`), so on the
/// Netflix WEB-DL DV MP4 (1/16000, 23.976 fps, B-frames) segment 33's boundary keyframe has
/// dts 3070672 = the target but pts 3072000 (two frames of reorder) — the old pts compare aborted
/// every reposition. Matroska Cues are pts and its packet dts is synthesized, so it stays on pts.
final class RemuxSeekLandingTests: XCTestCase {

    private let noTS = RemuxSeekLanding.noTS
    private let movTolerance: Int64 = 656        // one learned frame on the 1/16000 file

    func testIndexDomainByDemuxer() {
        XCTAssertTrue(RemuxSeekLanding.indexIsDTS(formatName: "mov,mp4,m4a,3gp,3g2,mj2"))
        XCTAssertFalse(RemuxSeekLanding.indexIsDTS(formatName: "matroska,webm"))
        XCTAssertFalse(RemuxSeekLanding.indexIsDTS(formatName: nil))
    }

    func testDeviceSegment33LandingIsAccepted() {
        XCTAssertTrue(RemuxSeekLanding.accepts(landedPTS: 3_072_000, landedDTS: 3_070_672,
                                               target: 3_070_672, tolerance: movTolerance))
        // The pre-fix rule (pts vs a dts target) rejects it — the device's ×4 abort.
        XCTAssertFalse(RemuxSeekLanding.accepts(landedPTS: 3_072_000, landedDTS: 3_070_672,
                                                target: 3_070_672, tolerance: movTolerance,
                                                indexIsDTS: false))
    }

    func testMovKeyframesBeforeTargetKeepScanningAndLaterOnesReject() {
        // The keyframe the BACKWARD seek lands on (one segment early) is skipped, not judged.
        XCTAssertEqual(RemuxSeekLanding.classify(pts: 2_975_232, dts: 2_973_904, target: 3_070_672,
                                                 tolerance: movTolerance, indexIsDTS: true), .keepScanning)
        // A keyframe a GOP late is a different keyframe → reject.
        XCTAssertEqual(RemuxSeekLanding.classify(pts: 3_168_768, dts: 3_167_440, target: 3_070_672,
                                                 tolerance: movTolerance, indexIsDTS: true), .reject)
        // Missing dts falls back to pts.
        XCTAssertEqual(RemuxSeekLanding.classify(pts: 3_070_672, dts: noTS, target: 3_070_672,
                                                 tolerance: movTolerance, indexIsDTS: true), .accept)
    }

    func testMkvLikeLanding() {
        let tol: Int64 = 42                       // 1/1000, ~24 fps
        let target: Int64 = 192_192
        XCTAssertTrue(RemuxSeekLanding.accepts(landedPTS: target, landedDTS: target, target: target,
                                               tolerance: tol, indexIsDTS: false))
        // Synthesized dts (pts − reorder) must not matter on a pts index.
        XCTAssertTrue(RemuxSeekLanding.accepts(landedPTS: target, landedDTS: target - 84, target: target,
                                               tolerance: tol, indexIsDTS: false))
        // A keyframe three 6 s segments late → reject.
        XCTAssertFalse(RemuxSeekLanding.accepts(landedPTS: target + 18_018, landedDTS: target + 18_018,
                                                target: target, tolerance: tol, indexIsDTS: false))
    }

    // MARK: - Copy-loop cut

    private typealias Pkt = (pts: Int64, dts: Int64, isKey: Bool)

    /// Replays the copy loop's cut over a packet stream; returns the index of each cutting packet.
    private func cuts(_ packets: [Pkt], boundaries: [Int64], firstNext: Int = 1, indexIsDTS: Bool) -> [Int] {
        var next = firstNext
        var out: [Int] = []
        for (i, p) in packets.enumerated() where p.isKey && next < boundaries.count {
            if RemuxSeekLanding.opensSegment(pts: p.pts, dts: p.dts, boundary: boundaries[next],
                                             indexIsDTS: indexIsDTS) {
                out.append(i); next += 1
            }
        }
        return out
    }

    func testConstantDurationMkvCutsOncePerBoundary() {
        // 1/1000, 40 ms frames, keyframe every 50 frames (2 s), dts == pts at keyframes.
        let packets: [Pkt] = (0..<500).map { i -> Pkt in
            let t = Int64(i) * 40
            return (pts: t, dts: t, isKey: i % 50 == 0)
        }
        let boundaries: [Int64] = [0, 6_000, 12_000, 18_000]
        let cutAt = cuts(packets, boundaries: boundaries, indexIsDTS: false)
        XCTAssertEqual(cutAt, [150, 300, 450])
        XCTAssertEqual(cutAt.map { packets[$0].pts }, Array(boundaries.dropFirst()))
    }

    func testBFrameMovCutsExactlyAtTheIndexedKeyframe() {
        // 1/16000, 664-tick frames, pts = dts + 2 frames. A scene-cut keyframe one frame before the
        // boundary keyframe: its pts (dts + 1328) passes the dts boundary — the pts compare cut there.
        let f: Int64 = 664
        var packets: [Pkt] = (0..<300).map { i -> Pkt in
            let dts = Int64(i) * f
            return (pts: dts + 2 * f, dts: dts, isKey: i % 100 == 0)
        }
        packets[199].isKey = true
        let boundaries: [Int64] = [0, 100 * f, 200 * f]
        XCTAssertEqual(cuts(packets, boundaries: boundaries, indexIsDTS: true), [100, 200])
        XCTAssertEqual(cuts(packets, boundaries: boundaries, indexIsDTS: false), [100, 199],
                       "pts compare cuts one keyframe early on B-frame mov")
    }
}
