import AVFoundation
import XCTest
@testable import NuvioTV

/// P4 (BUG-143): engine evidence → failure kind; only positive link evidence is remembered.
final class PlaybackFailureClassifierTests: XCTestCase {
    typealias C = PlaybackFailureClassifier

    private func log(_ lines: [String], watchdog: Bool = false) -> C.Verdict {
        C.fromMpvLog(lines, endFileError: "loading failed", watchdogFired: watchdog)
    }

    func testMpvHTTPLines() {
        XCTAssertEqual(log(["ffmpeg: HTTP error 404 Not Found"]), C.Verdict(.http, http: 404))
        XCTAssertEqual(log(["ffmpeg: Server returned 403 Forbidden (access denied)"]), C.Verdict(.http, http: 403))
        XCTAssertEqual(log(["ffmpeg: Server returned 4XX Client Error, but not one of 40{0,1,3,4}"]), C.Verdict(.http, http: 400))
        XCTAssertEqual(log(["ffmpeg: Server returned 5XX Server Error reply"]), C.Verdict(.http, http: 500))
        XCTAssertEqual(log(["stream: 401 Unauthorized"]), C.Verdict(.http, http: 401))
        XCTAssertEqual(log(["stream: 400 Bad Request"]), C.Verdict(.http, http: 400))
    }

    func testMixedRingHTTPWins() {
        XCTAssertEqual(log(["tcp: Connection refused", "ffmpeg: HTTP error 404"]), C.Verdict(.http, http: 404))
    }

    func testMpvNetworkLines() {
        for line in ["tcp: Connection refused", "tcp: Connection timed out", "tcp: Operation timed out",
                     "tcp: Failed to resolve hostname x.example", "tcp: Network is unreachable", "tcp: No route to host",
                     "tcp: Host is down", "tls: Connection reset by peer", "tls: TLS handshake failed", "tls: SSL error",
                     "gnutls: handshake failed"] {
            XCTAssertEqual(log([line]).kind, .network, line)
        }
        XCTAssertEqual(log([], watchdog: true).kind, .network)
        XCTAssertEqual(log(["ffmpeg: HTTP error 404"], watchdog: true).kind, .http)
    }

    func testMpvDecodeAndUnknown() {
        for line in ["ffmpeg: Invalid data found when processing input", "demux: Failed to recognize file format.",
                     "vd: could not find codec parameters", "cplayer: No video or audio streams selected."] {
            XCTAssertEqual(log([line]).kind, .decode, line)
        }
        XCTAssertEqual(log(["something else"]).kind, .unknown)
    }

    func testAVErrors() {
        XCTAssertEqual(C.fromAVError(C.httpNotFound), C.Verdict(.http, http: 404))
        XCTAssertEqual(C.fromAVError(C.httpForbidden), C.Verdict(.http, http: 403))
        XCTAssertEqual(C.fromAVError(C.httpUnauthorized), C.Verdict(.http, http: 401))
        XCTAssertEqual(C.fromAVError(C.httpBadRequest), C.Verdict(.http, http: 400))
        XCTAssertEqual(C.fromAVError(C.httpOther4xx), C.Verdict(.http, http: 400))
        XCTAssertEqual(C.fromAVError(C.httpServerError), C.Verdict(.http, http: 500))
        for code: Int32 in [-61, -60, -51, -65, -54, -64] { XCTAssertEqual(C.fromAVError(code).kind, .network) }
        XCTAssertEqual(C.fromAVError(-5, atOpen: true).kind, .network)
        XCTAssertEqual(C.fromAVError(-5).kind, .unknown)
        for code in [C.invalidData, C.decoderNotFound, C.demuxerNotFound] { XCTAssertEqual(C.fromAVError(code).kind, .decode) }
        XCTAssertEqual(C.fromAVError(C.exit).kind, .cancelled)
        XCTAssertEqual(C.fromAVError(-12345).kind, .unknown)
        // FFERRTAG spot check against the C value of AVERROR_HTTP_NOT_FOUND.
        XCTAssertEqual(C.httpNotFound, -0x3430_34F8)
        XCTAssertEqual(C.exit, -0x5449_5845)
    }

    func testNSErrors() {
        let remote = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(C.fromNSError(remote, origin: .remote).kind, .network)
        XCTAssertEqual(C.fromNSError(remote, origin: .loopback).kind, .noMedia)
        for code in [-1001, -1003, -1004, -1005, -1009, -1200, -1201, -1202, -1203, -1204, -1205, -1206] {
            XCTAssertEqual(C.fromNSError(NSError(domain: NSURLErrorDomain, code: code), origin: .remote).kind, .network, "\(code)")
        }
        XCTAssertEqual(C.fromNSError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), origin: .remote).kind, .cancelled)
        let nested = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: -1004)])
        XCTAssertEqual(C.fromNSError(nested, origin: .remote).kind, .network)
        let decode = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: "CoreMediaErrorDomain", code: -12927)])
        XCTAssertEqual(C.fromNSError(decode, origin: .loopback).kind, .decode)
        XCTAssertEqual(C.fromNSError(URLError(.notConnectedToInternet), origin: .remote).kind, .network)
        XCTAssertEqual(C.fromNSError(nil, origin: .remote).kind, .unknown)
    }

    func testOfflineOverride() {
        XCTAssertEqual(C.applyingPath(C.Verdict(.http, http: 404), pathSatisfied: false).kind, .offline)
        XCTAssertEqual(C.applyingPath(C.Verdict(.http, http: 404), pathSatisfied: true), C.Verdict(.http, http: 404))
    }

    func testRemembersLinkTruthTable() {
        let remembered: [PlaybackFailureKind] = [.http, .decode, .placeholder, .endedEarly, .noMedia, .unknown]
        let transient: [PlaybackFailureKind] = [.network, .offline, .cancelled, .local]
        remembered.forEach { XCTAssertTrue($0.remembersLink, $0.rawValue) }
        transient.forEach { XCTAssertFalse($0.remembersLink, $0.rawValue) }
    }
}
