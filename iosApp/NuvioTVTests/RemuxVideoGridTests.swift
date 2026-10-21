import XCTest
@testable import NuvioTV

/// W3-1 (BUG-199): the remux's video DTS grid. A Netflix WEB-DL MP4 on a 1/16000 timescale (23.976 fps,
/// durations cycling 667/667/668, B-frames) failed at segment 7 with movenc's `pts (590005) < dts
/// (590017)` because the old grid `anchor + (index − 6) · vDur` re-learned `vDur` from every packet and
/// jittered by ~index ticks; at every fragment start movenc also rewrote the opening keyframe's pts.
final class RemuxVideoGridTests: XCTestCase {

    private typealias Packet = (pts: Int64, duration: Int64, isKey: Bool, presentationIndex: Int)

    /// The pre-W3-1 video branch of the remux loop, verbatim (RemuxSession.swift @ 6baddab46,
    /// :1051-1063), kept here as the reference the new grid must reproduce on constant durations.
    private struct OldGrid {
        let slack: Int64 = 6
        var anchor: Int64
        var vDur: Int64 = 0
        var vIndex: Int64 = 0
        var vPrevDTS: Int64?
        mutating func reposition(anchor: Int64) { self.anchor = anchor; vIndex = 0; vPrevDTS = nil }
        mutating func stamp(pts inPTS: Int64, duration: Int64) -> (pts: Int64, dts: Int64) {
            let noTS = Int64.min
            var pts = inPTS
            if duration > 0 {
                vDur = duration
            } else if vDur == 0, pts != noTS, pts > anchor {
                vDur = pts - anchor
            }
            var dts = anchor + (vIndex - slack) * max(vDur, 1)
            if dts < 0 { dts = 0 }
            if pts != noTS, dts > pts { dts = pts }
            if let prev = vPrevDTS, dts <= prev { dts = prev + 1 }
            vPrevDTS = dts
            if pts == noTS { pts = anchor + vIndex * max(vDur, 1) }
            vIndex += 1
            return (pts, dts)
        }
    }

    /// Decode order of `total` frames: a closed GOP every `gop` frames (keyframe first), then
    /// mini-GOPs of `mini`: the anchor P-frame, then the hierarchical-B pyramid between.
    private func decodeOrder(total: Int, gop: Int = 36, mini: Int = 8) -> [Int] {
        var out: [Int] = []
        func pyramid(_ lo: Int, _ hi: Int) {
            guard hi - lo >= 2 else { return }
            let mid = (lo + hi) / 2
            out.append(mid); pyramid(lo, mid); pyramid(mid, hi)
        }
        var g0 = 0
        while g0 < total {
            out.append(g0)
            let end = min(g0 + gop, total)
            var a = g0
            while a + 1 < end {
                let b = min(a + mini, end - 1)
                out.append(b)
                pyramid(a, b)
                a = b
            }
            g0 += gop
        }
        return out
    }

    /// A stream in decode order: presentation time of frame n is Σ of the per-frame durations before
    /// it (`durations` cycles), the declared packet duration is the sample delta in DECODE order (what
    /// the mov demuxer hands out from stts), pts is offset by `anchor`.
    private func stream(total: Int, durations: [Int64], anchor: Int64 = 0, gop: Int = 36,
                        declared: ((Int) -> Int64)? = nil,
                        presentation: ((Int) -> Int64)? = nil) -> [Packet] {
        var pt: [Int64] = [0]
        for i in 0..<total { pt.append(pt[i] + durations[i % durations.count]) }
        let order = decodeOrder(total: total, gop: gop)
        XCTAssertEqual(order.sorted(), Array(0..<total))
        return order.enumerated().map { d, n -> Packet in
            let p = presentation?(n) ?? pt[n]
            let dur = declared?(d) ?? durations[d % durations.count]
            return (anchor + p, dur, n % gop == 0, n)
        }
    }

    // (a) The exact BUG-199 collision: previous dts 590016, grid at or above pts 590005.
    func testExactCollisionNeverYieldsPtsBelowDts() {
        var grid = RemuxVideoGrid(anchor: 0)
        grid.learnedDuration = 667
        grid.learnedFromDuration = true
        grid.slot = 594_200                // grid dts = 594200 − 6·667 = 590198 ≥ pts
        grid.index = 880
        grid.prevDTS = 590_016
        grid.prevDuration = 667
        let s = grid.stamp(pts: 590_005, duration: 667)
        XCTAssertEqual(s.dts, 590_017, "clamp to pts, then the strict-monotonic bump")
        XCTAssertGreaterThanOrEqual(s.pts, s.dts)
        XCTAssertEqual(s.pts, 590_017)
        XCTAssertEqual(grid.ptsNetFirings, 1)
        // The old rule produced the write error on the same input.
        var old = OldGrid(anchor: 0, vDur: 667, vIndex: 891, vPrevDTS: 590_016)
        let o = old.stamp(pts: 590_005, duration: 667)
        XCTAssertLessThan(o.pts, o.dts, "reference: the old formula hands movenc pts < dts")
    }

    // (b) 3000 packets, 667/667/668, mini-GOP 8, keyframe every 36, fragment every 144 frames.
    func testNetflixCadenceStaysOrderedWithNoRewrites() {
        let packets = stream(total: 3000, durations: [667, 667, 668])
        var grid = RemuxVideoGrid(anchor: 0)
        var old = OldGrid(anchor: 0)
        var prev: RemuxVideoGrid.Stamp?
        var oldPrev: (dts: Int64, dur: Int64)?
        var fragmentStarts = 0
        var oldFragmentViolations = 0
        for p in packets {
            let opens = p.isKey && p.presentationIndex % 144 == 0 && p.presentationIndex > 0
            let s = grid.stamp(pts: p.pts, duration: p.duration, fragmentStart: opens)
            XCTAssertGreaterThanOrEqual(s.pts, s.dts, "frame \(p.presentationIndex)")
            XCTAssertEqual(s.pts, p.pts, "pts rewritten at frame \(p.presentationIndex)")
            XCTAssertEqual(s.duration, p.duration)
            if let prev {
                XCTAssertGreaterThan(s.dts, prev.dts, "dts not strictly rising at frame \(p.presentationIndex)")
                if opens {
                    fragmentStarts += 1
                    // movenc check_pkt: a fragment's first dts ≥ previous dts + previous duration.
                    XCTAssertGreaterThanOrEqual(s.dts, prev.dts + prev.duration,
                                                "fragment start at frame \(p.presentationIndex)")
                }
            }
            prev = s
            let o = old.stamp(pts: p.pts, duration: p.duration)
            if opens, let op = oldPrev, o.dts < op.dts + op.dur { oldFragmentViolations += 1 }
            oldPrev = (o.dts, p.duration)
        }
        XCTAssertEqual(fragmentStarts, 20)
        XCTAssertEqual(grid.netFirings, 0, "the stable grid needs no net")
        XCTAssertEqual(grid.clampCount, 0)
        XCTAssertGreaterThan(oldFragmentViolations, 0, "reference: the old grid trips movenc's pts rewrite")
    }

    // (c) Constant durations (MKV-like): the new grid gives the old formula's stamps exactly.
    func testConstantDurationStreamsMatchTheOldFormula() {
        // 23.976 at 1/24000 (exact 1001-tick frames), mini-GOP 8 / GOP 36.
        assertMatchesOld(stream(total: 2000, durations: [1001]))
        // Matroska at 1/1000 → movenc 1/16000: declared default duration 41 ms (656 ticks), pts on
        // the millisecond grid (true frame time rounded to ms, ×16). The grid lags pts; no clamps.
        let msPTS: (Int) -> Int64 = { n in Int64((Double(n) * 1001.0 / 24.0).rounded()) * 16 }
        assertMatchesOld(stream(total: 2000, durations: [656], presentation: msPTS))
        // Same with a nonzero anchor and a second run (reposition keeps the learned duration).
        assertMatchesOld(stream(total: 600, durations: [1001], anchor: 4_804_800),
                         then: stream(total: 600, durations: [1001], anchor: 1_201_200))
    }

    private func assertMatchesOld(_ run1: [Packet], then run2: [Packet]? = nil,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let a1 = run1.first!.pts
        var grid = RemuxVideoGrid(anchor: a1)
        var old = OldGrid(anchor: a1)
        func replay(_ packets: [Packet]) {
            for (i, p) in packets.enumerated() {
                let opens = i > 0 && p.isKey && p.presentationIndex % 144 == 0
                let s = grid.stamp(pts: p.pts, duration: p.duration, fragmentStart: opens)
                let o = old.stamp(pts: p.pts, duration: p.duration)
                XCTAssertEqual(s.dts, o.dts, "dts at decode \(i)", file: file, line: line)
                XCTAssertEqual(s.pts, o.pts, "pts at decode \(i)", file: file, line: line)
            }
        }
        replay(run1)
        if let run2 {
            grid.reposition(anchor: run2.first!.pts)
            old.reposition(anchor: run2.first!.pts)
            replay(run2)
        }
        XCTAssertEqual(grid.netFirings, 0, file: file, line: line)
    }

    // (d) Reposition: the grid restarts at the new anchor, forgets the previous run's dts (a backward
    // seek must not be bumped above the old run), keeps the learned duration.
    func testRepositionRestartsAtTheNewAnchor() {
        var grid = RemuxVideoGrid(anchor: 0)
        for p in stream(total: 300, durations: [667, 667, 668]) {
            _ = grid.stamp(pts: p.pts, duration: p.duration)
        }
        XCTAssertEqual(grid.learnedDuration, 667)
        let anchor: Int64 = 96_096
        grid.reposition(anchor: anchor)
        XCTAssertEqual(grid.index, 0)
        XCTAssertNil(grid.prevDTS)
        let packets = stream(total: 144, durations: [668, 667, 667], anchor: anchor)
        let first = grid.stamp(pts: packets[0].pts, duration: packets[0].duration)
        XCTAssertEqual(first.dts, anchor - 6 * 667, "anchor minus the learned reorder slack")
        XCTAssertEqual(first.pts, anchor)
        var prevDTS = first.dts
        for p in packets.dropFirst() {
            let s = grid.stamp(pts: p.pts, duration: p.duration)
            XCTAssertGreaterThanOrEqual(s.pts, s.dts)
            XCTAssertGreaterThan(s.dts, prevDTS)
            prevDTS = s.dts
        }
        XCTAssertEqual(grid.learnedDuration, 667, "learned once, kept across runs")
        XCTAssertEqual(grid.netFirings, 0)
    }

    // The fragment-start net: when the previous packet's dts + duration is above the grid (here the
    // grid is forced behind), the opening keyframe is lifted to it instead of movenc rewriting pts.
    func testFragmentStartNetLiftsTheKeyframe() {
        var grid = RemuxVideoGrid(anchor: 0)
        grid.learnedDuration = 672
        grid.learnedFromDuration = true
        grid.slot = 96_000                 // grid dts 91968 → bumped to 92065, below 92064 + 672
        grid.prevDTS = 92_064
        grid.prevDuration = 672
        let s = grid.stamp(pts: 96_768, duration: 672, fragmentStart: true)
        XCTAssertEqual(s.dts, 92_736)
        XCTAssertEqual(s.pts, 96_768, "the keyframe keeps its presentation offset")
        XCTAssertEqual(grid.fragmentNetFirings, 1)
        XCTAssertEqual(grid.ptsNetFirings, 0)
    }

    // An outlier duration does not shift the rest of the run's grid.
    func testOutlierDurationIsReplacedByTheUnit() {
        var grid = RemuxVideoGrid(anchor: 0)
        _ = grid.stamp(pts: 0, duration: 667)
        let s = grid.stamp(pts: 5336, duration: 1_000_000)
        XCTAssertEqual(s.duration, 667)
        XCTAssertEqual(grid.slot, 2 * 667)
    }

    // Missing pts is synthesised at the packet's slot and never lands below dts.
    func testMissingPtsIsSynthesisedAtTheSlot() {
        var grid = RemuxVideoGrid(anchor: 1000)
        let a = grid.stamp(pts: RemuxVideoGrid.noTS, duration: 1001)
        XCTAssertEqual(a.pts, 1000)
        let b = grid.stamp(pts: RemuxVideoGrid.noTS, duration: 1001)
        XCTAssertEqual(b.pts, 2001)
        XCTAssertGreaterThanOrEqual(b.pts, b.dts)
    }
}
