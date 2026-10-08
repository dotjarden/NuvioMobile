import Darwin
import ImageIO
import XCTest
@testable import NuvioTV

/// Integration tests for the P3 keyframe thumbnailer against the smoke rig's range server
/// (`build/smoke/range_server.py` on :8000). Skipped when the fixture does not answer a HEAD.
final class KeyframeThumbnailerTests: XCTestCase {
    private static let fixture = URL(string: "http://127.0.0.1:8000/test-long.mkv")!

    private func requireFixture() async throws {
        var req = URLRequest(url: Self.fixture)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 2
        let ok = (try? await URLSession.shared.data(for: req)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        try XCTSkipUnless(ok, "smoke range server not running on 127.0.0.1:8000")
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
        print(String(format: "[ThumbsTest] open=%.0fms index=%d openRead=%lldKB kf=%.3f took=%.1fms dec=%.1fms bytes=%lldKB",
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
        let t = KeyframeThumbnailer(url: URL(string: "http://127.0.0.1:8000/no-such-file.mkv")!, headers: [:])
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
