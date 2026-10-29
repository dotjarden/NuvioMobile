import Darwin
import ImageIO
import XCTest
@testable import NuvioTV

/// Integration tests for the P3 keyframe thumbnailer against the smoke rig's range server
/// (`build/smoke/range_server.py`). The fixture URL comes from `TEST_RUNNER_THUMB_FIXTURE_URL`
/// (default `http://127.0.0.1:8000/test-long.mkv`); review r1 P3 #10: when it does not answer, the
/// integration tests SKIP with a loud message, and a gate's pass count does not show that, so the
/// batch record states the skip count with the gate.
final class KeyframeThumbnailerTests: XCTestCase {
    private static let fixture: URL = {
        let raw = ProcessInfo.processInfo.environment["THUMB_FIXTURE_URL"] ?? ""
        return URL(string: raw.isEmpty ? "http://127.0.0.1:8000/test-long.mkv" : raw)!
    }()

    private func requireFixture() async throws {
        var req = URLRequest(url: Self.fixture)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 2
        let ok = (try? await URLSession.shared.data(for: req)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        if !ok { print("[ThumbsTest] SKIPPED: fixture \(Self.fixture.absoluteString) did not answer a HEAD") }
        try XCTSkipUnless(ok, "THUMBNAILER INTEGRATION TEST SKIPPED: fixture \(Self.fixture.absoluteString) did not answer "
                          + "(start build/smoke/range_server.py or set TEST_RUNNER_THUMB_FIXTURE_URL)")
    }

    /// The fixture's sibling path on the same server.
    private static func sibling(_ name: String) -> URL {
        fixture.deletingLastPathComponent().appendingPathComponent(name)
    }

    // MARK: Review r1 (pure)

    /// P1: the budget charges consumed bytes plus a whole range per request.
    func testChargeAddsAWholeRangePerRequest() {
        XCTAssertEqual(KeyframeThumbnailer.charge(consumed: 32 * 1024, requests: 1, requestBytes: 256 * 1024),
                       288 * 1024)
        XCTAssertEqual(KeyframeThumbnailer.charge(consumed: 0, requests: 2, requestBytes: 1024), 2048)
        XCTAssertEqual(KeyframeThumbnailer.charge(consumed: -5, requests: -1, requestBytes: 1024), 0)
        XCTAssertEqual(KeyframeThumbnailer.requestBytes(width: 1920), 256 * 1024)
        XCTAssertEqual(KeyframeThumbnailer.requestBytes(width: 3840), 1024 * 1024)
        XCTAssertLessThanOrEqual(KeyframeThumbnailer.openRequestBytes, 512 * 1024)
    }

    /// Review r2 P2 #1, P3 #6: an open is charged the requests it makes (counted on the logging
    /// range server: five on a first open of the fixture, one on a reopen), plus a range per open
    /// range crossed, plus two for an MP4 that may keep its index at the end.
    func testOpenRequestsCountTheMeasuredSeeksAndTheRangesCrossed() {
        let mkv = "matroska,webm", mp4 = "mov,mp4,m4a,3gp,3g2,mj2"
        XCTAssertEqual(KeyframeThumbnailer.openRequests(reopen: false, container: mkv, consumed: 452 * 1024), 5)
        XCTAssertEqual(KeyframeThumbnailer.openRequests(reopen: true, container: mkv, consumed: 8 * 1024), 1)
        XCTAssertEqual(KeyframeThumbnailer.openRequests(reopen: false, container: mp4, consumed: 0), 7)
        XCTAssertEqual(KeyframeThumbnailer.openRequests(reopen: true, container: mp4, consumed: 0), 3)
        XCTAssertEqual(KeyframeThumbnailer.openRequests(reopen: false, container: mkv, consumed: 1536 * 1024), 5,
                       "bytes an open read through are already in consumed and are not charged again as requests (r3 P3 #2)")
        XCTAssertEqual(KeyframeThumbnailer.openRequests(reopen: false, container: "", consumed: -1), 5)
        XCTAssertEqual(KeyframeThumbnailer.reopenFirstFrameRequests, 3)
    }

    /// Review r2 P2 #1: the host is still sending when a range larger than 256 KB was read short
    /// of a range boundary (or the read is unknown); a 256 KB range always finishes at the host.
    func testRequestLeftOpenOnlyForLargeRangesReadShort() {
        let k = 1024
        XCTAssertFalse(KeyframeThumbnailer.requestLeftOpen(rangeBytes: 256 * k, httpRead: 32 * 1024))
        XCTAssertFalse(KeyframeThumbnailer.requestLeftOpen(rangeBytes: 256 * k, httpRead: nil))
        XCTAssertTrue(KeyframeThumbnailer.requestLeftOpen(rangeBytes: 1024 * k, httpRead: 2_300_000))
        XCTAssertFalse(KeyframeThumbnailer.requestLeftOpen(rangeBytes: 1024 * k, httpRead: 2 * 1024 * 1024),
                       "read to a range end: the host closed")
        XCTAssertTrue(KeyframeThumbnailer.requestLeftOpen(rangeBytes: 1024 * k, httpRead: nil))
        XCTAssertTrue(KeyframeThumbnailer.requestLeftOpen(rangeBytes: 512 * k, httpRead: 0))
    }

    /// P2 #2: enough entries AND the last one at 80 % of the duration.
    func testIndexMustSpanEightyPercentOfTheDuration() {
        let full = stride(from: 0.0, through: 590, by: 2).map { $0 }
        XCTAssertTrue(KeyframeThumbnailer.indexUsable(full, durationSec: 600))
        let startOnly = stride(from: 0.0, through: 120, by: 2).map { $0 }        // 61 entries, first 20 %
        XCTAssertFalse(KeyframeThumbnailer.indexUsable(startOnly, durationSec: 600))
        XCTAssertFalse(KeyframeThumbnailer.indexUsable([0, 300, 590], durationSec: 600), "too few entries")
        XCTAssertTrue(KeyframeThumbnailer.indexUsable([0, 10, 20], durationSec: 0), "unknown duration: count only")
        XCTAssertFalse(KeyframeThumbnailer.indexUsable([0], durationSec: 0))
        let edge = stride(from: 0.0, through: 480, by: 2).map { $0 }            // last = 0.8 × 600
        XCTAssertTrue(KeyframeThumbnailer.indexUsable(edge, durationSec: 600))
    }

    /// P2 #2: the gate's byte ceiling, with an injected counter.
    func testGateByteCeilingInterruptsAndReports() {
        let gate = ThumbInterruptGate()
        var counter: Int64 = 0
        let lock = NSLock()
        gate.armBytes(limit: 16) { lock.lock(); defer { lock.unlock() }; return counter }
        XCTAssertFalse(gate.shouldInterrupt)
        XCTAssertFalse(gate.byteLimitHit)
        lock.lock(); counter = 15; lock.unlock()
        XCTAssertFalse(gate.shouldInterrupt)
        lock.lock(); counter = 16; lock.unlock()
        XCTAssertTrue(gate.shouldInterrupt)
        XCTAssertTrue(gate.byteLimitHit)
        XCTAssertFalse(gate.aborted, "a byte stop is not a close")
        gate.disarmBytes()
        XCTAssertFalse(gate.shouldInterrupt)
        XCTAssertTrue(gate.byteLimitHit, "kept until the next arm")
        gate.armBytes(limit: 100) { 0 }
        XCTAssertFalse(gate.byteLimitHit)
    }

    // MARK: Review r1 (fixture)

    /// P2 #2: on a Cue-less MKV (`test-nocues.mkv`: the fixture with its Cues element turned into
    /// an EBML Void and its SeekHead entry renamed, duration kept) the priming seek is a linear
    /// scan; it stops at the 16 MB cap, the index covers only the start, and the open refuses
    /// `noIndex`. Make the file next to the fixture with:
    /// `python3 -c "d=bytearray(open('test-long.mkv','rb').read());I=bytes([0x1C,0x53,0xBB,0x6B]);s=d.find(I);c=d.rfind(I);b=d[c+4];l=8-b.bit_length()+1;z=int.from_bytes(d[c+4:c+4+l],'big')&((1<<(7*l))-1);T=4+l+z;d[c]=0xEC;d[c+1]=1;d[c+2:c+9]=(T-9).to_bytes(7,'big');d[s+3]=0x6C;open('test-nocues.mkv','wb').write(d)"`
    func testCuelessFileStopsAtThePrimingCapAndRefusesNoIndex() async throws {
        try await requireFixture()
        let url = Self.sibling("test-nocues.mkv")
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 2
        let ok = (try? await URLSession.shared.data(for: req)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        if !ok { print("[ThumbsTest] SKIPPED: \(url.absoluteString) missing (recipe in the test's comment)") }
        try XCTSkipUnless(ok, "CUE-LESS PRIMING TEST SKIPPED: \(url.absoluteString) did not answer (recipe in the test's comment)")
        let t = KeyframeThumbnailer(url: url, headers: [:])
        defer { t.close() }
        let start = Date()
        let r = await t.open()
        guard case .refused(let reason) = r else { return XCTFail("a Cue-less file must refuse") }
        XCTAssertEqual(reason, .noIndex)
        print(String(format: "[ThumbsTest] cue-less open: refused noIndex after %lldKB read, %lldKB charged, %.2f s",
                     t.bytesRead / 1024, t.bytesCharged / 1024, Date().timeIntervalSince(start)))
        // The cap plus what avio had buffered when the poll fired.
        XCTAssertLessThan(t.bytesRead, KeyframeThumbnailer.primingByteCap + 2 * 1024 * 1024)
        XCTAssertGreaterThan(t.bytesRead, KeyframeThumbnailer.primingByteCap / 2, "the scan never reached the cap")
    }

    /// P2 #2, review r2 P3 #5: a 1-byte priming cap fires on the fixture (the read that loads the
    /// tail Cues still goes through: the gate polls before each read, so the overshoot is one
    /// read), the index it kept spans the file, and a frame decodes afterwards on the same
    /// context, through the `error` / `eof_reached` reset that follows a byte stop.
    func testFrameDecodesAfterThePrimingCapFired() async throws {
        try await requireFixture()
        let t = KeyframeThumbnailer(url: Self.fixture, headers: [:], primingByteCap: 1)
        defer { t.close() }
        guard case .ready(let facts) = await t.open() else { return XCTFail("Cues loaded, the open must succeed") }
        XCTAssertTrue(t.primingCapHit, "the 1-byte cap never fired: the test proves nothing")
        XCTAssertTrue(KeyframeThumbnailer.indexUsable(facts.keyframeIndex, durationSec: facts.durationSec))
        guard case .frame(_, let kf, _, _, _, _) = await t.frame(at: 300, urgent: true) else {
            return XCTFail("no frame after the priming cap fired")
        }
        XCTAssertLessThanOrEqual(kf, 300.05)
        XCTAssertGreaterThan(kf, 290)
        // And a second seek on the same context.
        guard case .frame = await t.frame(at: 120, urgent: true) else { return XCTFail("no second frame") }
    }

    /// P1: a reopen with the first open's facts skips priming, still decodes, and charges
    /// at least a range per frame.
    func testReopenWithKnownFactsDecodes() async throws {
        try await requireFixture()
        let first = KeyframeThumbnailer(url: Self.fixture, headers: [:])
        guard case .ready(let facts) = await first.open() else { first.close(); return XCTFail("open refused") }
        first.close()
        let t = KeyframeThumbnailer(url: Self.fixture, headers: [:], knownFacts: facts)
        defer { t.close() }
        guard case .ready(let again) = await t.open() else { return XCTFail("reopen refused") }
        XCTAssertEqual(again.keyframeIndex, facts.keyframeIndex)
        let afterOpen = t.bytesCharged
        guard case .frame(_, let kf, _, _, _, let charged) = await t.frame(at: 300, urgent: true) else {
            return XCTFail("no frame after reopen")
        }
        XCTAssertLessThanOrEqual(kf, 300.05)
        XCTAssertGreaterThan(kf, 290)
        XCTAssertGreaterThanOrEqual(charged, Int64(KeyframeThumbnailer.requestBytes(width: 1920)))
        XCTAssertEqual(t.bytesCharged - afterOpen, charged)
        // Review r2 P2 #1, P3 #6: a reopen is charged one open range plus what it read, not five,
        // and a 1080p frame's 256 KB range finishes at the host.
        XCTAssertLessThan(afterOpen, 2 * Int64(KeyframeThumbnailer.openRequestBytes))
        XCTAssertFalse(t.lastRequestLeftOpen)
        print(String(format: "[ThumbsTest] reopen read=%lldKB charged open=%lldKB frame=%lldKB",
                     t.bytesRead / 1024, afterOpen / 1024, charged / 1024))
    }

    func testFrameAt120StampsTheKeyframeBefore() async throws {
        try await requireFixture()
        let t = KeyframeThumbnailer(url: Self.fixture, headers: [:])
        defer { t.close() }
        guard case .ready(let facts) = await t.open() else { return XCTFail("open refused") }
        XCTAssertTrue(facts.container.contains("matroska"), facts.container)
        XCTAssertGreaterThanOrEqual(facts.keyframeIndex.count, Int(facts.durationSec / 30) + 1)
        let afterOpen = t.bytesRead
        guard case .frame(let image, let kf, let took, let dec, _, let bytes) = await t.frame(at: 120, urgent: true) else {
            return XCTFail("no frame at 120")
        }
        XCTAssertEqual(image.width, 320)
        XCTAssertGreaterThan(image.height, 100)
        XCTAssertGreaterThanOrEqual(kf, 118)
        XCTAssertLessThanOrEqual(kf, 120.05)
        XCTAssertGreaterThan(bytes, 0)
        XCTAssertGreaterThan(Self.lumaSpread(image), 20, "the decoded keyframe looks flat")
        if let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thumb120.png") as CFURL,
            "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("[ThumbsTest] wrote \(NSTemporaryDirectory())thumb120.png")
        }
        print(String(format: "[ThumbsTest] open=%.0fms index=%ld openRead=%lldKB kf=%.3f took=%.1fms dec=%.1fms bytes=%lldKB",
                     facts.openMs, facts.keyframeIndex.count, afterOpen / 1024, kf, took, dec, bytes / 1024))
        // A second request inside the same GOP lands on the same keyframe (the duplicate path).
        guard case .frame(_, let kf2, _, _, _, _) = await t.frame(at: 121, urgent: false) else {
            return XCTFail("no frame at 121")
        }
        XCTAssertEqual(kf2, kf, accuracy: 0.001)
        // Ten keyframes across the file: bytes per keyframe on the fixture.
        var total: Int64 = 0, tooks: [Double] = []
        for k in 1...10 {
            if case .frame(_, _, let tk, _, _, let b) = await t.frame(at: Double(k) * 50, urgent: false) {
                total += b; tooks.append(tk)
            }
        }
        XCTAssertEqual(tooks.count, 10)
        print(String(format: "[ThumbsTest] 10 keyframes: %.1fKB per keyframe, took median %.1fms, total read %.0fKB",
                     Double(total) / 10 / 1024, tooks.sorted()[5], Double(t.bytesRead) / 1024))
    }

    /// Max minus min of the green channel over the image (bgr0, 4 bytes per pixel).
    private static func lumaSpread(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return 0 }
        var lo = 255, hi = 0
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let g = Int(p[y * image.bytesPerRow + x * 4 + 1])
                lo = min(lo, g); hi = max(hi, g)
            }
        }
        return hi - lo
    }

    func testCloseBeforeOpenAndTwiceIsSafe() async {
        let t = KeyframeThumbnailer(url: Self.fixture, headers: [:])
        t.close()
        t.close()
        guard case .refused(.modeOff) = await t.open() else { return XCTFail("open after close must refuse") }
        guard case .aborted = await t.frame(at: 10, urgent: true) else { return XCTFail("frame after close must abort") }
    }

    func testMissingFileIsHTTPRefused() async throws {
        try await requireFixture()
        let t = KeyframeThumbnailer(url: Self.sibling("no-such-file.mkv"), headers: [:])
        defer { t.close() }
        guard case .refused(let reason) = await t.open() else { return XCTFail("a 404 must refuse") }
        XCTAssertEqual(reason, .httpRefused)
    }

    /// A listener that accepts the connection (kernel backlog) and never answers: `close()` 100 ms
    /// into `open()` returns the open within 400 ms.
    func testCloseAbortsAStalledOpen() async throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 4), 0)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        let t = KeyframeThumbnailer(url: URL(string: "http://127.0.0.1:\(port)/stall.mkv")!, headers: [:])
        Task.detached {
            try? await Task.sleep(nanoseconds: 100_000_000)
            t.close()
        }
        let start = Date()
        let r = await t.open()
        let elapsed = Date().timeIntervalSince(start)
        guard case .refused = r else { return XCTFail("a stalled open must refuse") }
        XCTAssertLessThan(elapsed, 0.4, "close did not abort the open in time")
    }

    func testHTTPErrorTags() {
        func tag(_ a: UInt8, _ b: Character, _ c: Character, _ d: Character) -> Int32 {
            -(Int32(a) | Int32(b.asciiValue!) << 8 | Int32(c.asciiValue!) << 16 | Int32(d.asciiValue!) << 24)
        }
        XCTAssertTrue(KeyframeThumbnailer.isHTTPError(tag(0xF8, "4", "0", "3")))
        XCTAssertTrue(KeyframeThumbnailer.isHTTPError(tag(0xF8, "4", "2", "9")))
        XCTAssertTrue(KeyframeThumbnailer.isHTTPError(tag(0xF8, "5", "X", "X")))
        XCTAssertFalse(KeyframeThumbnailer.isHTTPError(tag(UInt8(ascii: "E"), "X", "I", "T")))
        XCTAssertFalse(KeyframeThumbnailer.isHTTPError(-5))
        XCTAssertFalse(KeyframeThumbnailer.isHTTPError(0))
    }
}
