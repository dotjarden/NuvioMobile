import AVFoundation
import Foundation

/// P4 (BUG-143): maps engine evidence (mpv log lines, FFmpeg AVERROR codes, NSErrors) to a
/// `PlaybackFailureKind`. Pure. Only positive evidence against the link is remembered; network,
/// offline, cancelled and our own engine's failures are not (`PlaybackFailureKind.remembersLink`).
nonisolated enum PlaybackFailureClassifier {
    struct Verdict: Equatable {
        let kind: PlaybackFailureKind
        let httpStatus: Int?
        init(_ kind: PlaybackFailureKind, http: Int? = nil) { self.kind = kind; self.httpStatus = http }
    }

    /// Where an NSError's URL pointed: the remote host, or our own loopback server. [C-7]
    enum Origin { case remote, loopback }

    // MARK: mpv log

    /// HTTP evidence wins over network evidence (a refused retry followed by a 404 is a dead link),
    /// network wins over decode (a cut connection garbles the demuxer too). A fired start watchdog
    /// with no network line is `.unknown`, which IS remembered (spec decision 17): the link never
    /// produced media while the host was reachable. The caller's `applyingPath` still turns it into
    /// `.offline` when there was no network path, and a network line in the ring keeps `.network`.
    static func fromMpvLog(_ lines: [String], endFileError: String?, watchdogFired: Bool) -> Verdict {
        let all = lines + (endFileError.map { [$0] } ?? [])
        for line in all { if let status = httpStatus(inLog: line) { return Verdict(.http, http: status) } }
        if all.contains(where: isNetworkLine) { return Verdict(.network) }
        if all.contains(where: isDecodeLine) { return Verdict(.decode) }
        return Verdict(.unknown)
    }

    static func httpStatus(inLog line: String) -> Int? {
        for pattern in [#"HTTP error (\d{3})"#, #"Server returned (\d{3})"#] {
            if let r = line.range(of: pattern, options: .regularExpression) {
                let digits = line[r].filter(\.isNumber)
                if let code = Int(digits.suffix(3)) { return code }
            }
        }
        if line.contains("Server returned 4XX") { return 400 }
        if line.contains("Server returned 5XX") { return 500 }
        for (text, code) in [("400 Bad Request", 400), ("401 Unauthorized", 401), ("403 Forbidden", 403), ("404 Not Found", 404)]
        where line.contains(text) { return code }
        return nil
    }

    private static let networkPhrases = [
        "Connection refused", "Connection timed out", "Operation timed out", "Failed to resolve hostname",
        "Network is unreachable", "No route to host", "Host is down", "Connection reset by peer",
    ]
    private static func isNetworkLine(_ line: String) -> Bool {
        if networkPhrases.contains(where: { line.localizedCaseInsensitiveContains($0) }) { return true }
        let lower = line.lowercased()
        return (lower.contains("tls") || lower.contains("ssl") || lower.contains("gnutls"))
            && (lower.contains("handshake") || lower.contains("error") || lower.contains("fail"))
    }

    private static let decodePhrases = [
        "Invalid data found when processing input", "Failed to recognize file format", "could not find codec",
        "No video or audio streams selected",
    ]
    private static func isDecodeLine(_ line: String) -> Bool {
        decodePhrases.contains { line.localizedCaseInsensitiveContains($0) }
    }

    // MARK: FFmpeg AVERROR

    /// FFERRTAG(a, b, c, d) = -MKTAG(a, b, c, d); the C macros do not import into Swift.
    static func ffErrTag(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int32 {
        -(Int32(a) | Int32(b) << 8 | Int32(c) << 16 | Int32(d) << 24)
    }
    static let httpBadRequest = ffErrTag(0xF8, 0x34, 0x30, 0x30)     // 0xF8 '4' '0' '0'
    static let httpUnauthorized = ffErrTag(0xF8, 0x34, 0x30, 0x31)
    static let httpForbidden = ffErrTag(0xF8, 0x34, 0x30, 0x33)
    static let httpNotFound = ffErrTag(0xF8, 0x34, 0x30, 0x34)
    static let httpOther4xx = ffErrTag(0xF8, 0x34, 0x58, 0x58)      // '4' 'X' 'X'
    static let httpServerError = ffErrTag(0xF8, 0x35, 0x58, 0x58)   // '5' 'X' 'X'
    static let invalidData = ffErrTag(0x49, 0x4E, 0x44, 0x41)       // 'I' 'N' 'D' 'A'
    static let decoderNotFound = ffErrTag(0xF8, 0x44, 0x45, 0x43)   // 0xF8 'D' 'E' 'C'
    static let demuxerNotFound = ffErrTag(0xF8, 0x44, 0x45, 0x4D)   // 0xF8 'D' 'E' 'M'
    static let exit = ffErrTag(0x45, 0x58, 0x49, 0x54)              // 'E' 'X' 'I' 'T'

    /// `atOpen`: the code came from opening the input, where FFmpeg's TCP layer maps a resolve
    /// failure to EIO; anywhere past the open EIO stays `.unknown`.
    static func fromAVError(_ code: Int32, atOpen: Bool = false) -> Verdict {
        switch code {
        case httpBadRequest: return Verdict(.http, http: 400)
        case httpUnauthorized: return Verdict(.http, http: 401)
        case httpForbidden: return Verdict(.http, http: 403)
        case httpNotFound: return Verdict(.http, http: 404)
        case httpOther4xx: return Verdict(.http, http: 400)
        case httpServerError: return Verdict(.http, http: 500)
        case invalidData, decoderNotFound, demuxerNotFound: return Verdict(.decode)
        case exit: return Verdict(.cancelled)
        case -61, -60, -51, -65, -54, -64: return Verdict(.network)   // ECONNREFUSED ETIMEDOUT ENETUNREACH EHOSTUNREACH ECONNRESET EHOSTDOWN
        case -5 where atOpen: return Verdict(.network)                // EIO at open
        default: return Verdict(.unknown)
        }
    }

    // MARK: NSError

    static let remoteNetworkURLCodes: Set<Int> = [
        NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
        NSURLErrorNotConnectedToInternet, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
        NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired,
    ]
    /// AVFoundation decode / format failures.
    static let avFoundationDecodeCodes: Set<Int> = [
        AVError.Code.decodeFailed.rawValue, AVError.Code.fileFormatNotRecognized.rawValue,
        AVError.Code.decoderNotFound.rawValue, AVError.Code.failedToParse.rawValue,
    ]
    /// CoreMedia playlist/format parse failures (-12927 "cannot parse", -12642 playlist parse).
    static let coreMediaDecodeCodes: Set<Int> = [-12927, -12642, -12644, -12645]

    /// Walks `NSUnderlyingErrorKey`. On the loopback origin any URL-loading error means our own
    /// server failed to deliver: before playback started that is `.noMedia` (the remote host was
    /// reachable, the remux opened it, and nothing usable came out). `midPlay`: once playback has
    /// started it is our engine's limit (r1 P3: e.g. a seek past the remux frontier that the JIT
    /// server fast-503s), so `.local`, never remembered.
    static func fromNSError(_ error: Error?, origin: Origin, midPlay: Bool = false) -> Verdict {
        var current = error.map { $0 as NSError }
        var depth = 0
        var fallback = Verdict(.unknown)
        while let e = current, depth < 8 {
            switch e.domain {
            case NSURLErrorDomain:
                if e.code == NSURLErrorCancelled { return Verdict(.cancelled) }
                if origin == .loopback { return Verdict(midPlay ? .local : .noMedia) }
                if remoteNetworkURLCodes.contains(e.code) { return Verdict(.network) }
            case AVFoundationErrorDomain where avFoundationDecodeCodes.contains(e.code),
                 "CoreMediaErrorDomain" where coreMediaDecodeCodes.contains(e.code):
                fallback = Verdict(.decode)
            default:
                break
            }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return fallback
    }

    // MARK: Native engine stages

    /// r1 P3: `RemuxSession` / coordinator failure stages that are limits of our own engine, not
    /// evidence against the link (mpv plays these files): `.local`, never remembered.
    static let engineInternalStages: Set<String> = [
        "no segment map", "no usable keyframe index", "server bind failed", "alloc input ctx",
        "packet_alloc", "output context", "audio output context", "audio transcoder init",
    ]
    static func isEngineInternalStage(_ stage: String) -> Bool {
        engineInternalStages.contains(stage) || stage.hasPrefix("DV P7 converter init")
    }

    /// A native pre-playback or remux failure: an engine-internal stage → `.local`, then the
    /// remux's FFmpeg code if it has one, else "no segments produced" → `.noMedia`, else `.unknown`.
    static func fromNativeStage(_ stage: String, errorCode: Int32?, atOpen: Bool) -> Verdict {
        if isEngineInternalStage(stage) { return Verdict(.local) }
        if let errorCode { return fromAVError(errorCode, atOpen: atOpen) }
        return Verdict(stage == "no segments produced" ? .noMedia : .unknown)
    }

    /// No usable network path at the moment of failure → `.offline`, whatever else was seen.
    static func applyingPath(_ v: Verdict, pathSatisfied: Bool) -> Verdict {
        pathSatisfied ? v : Verdict(.offline)
    }
}

/// P4 (BUG-143): the last 16 mpv `warn`/`error`/`fatal` log lines of the CURRENT file, written on
/// the mpv event queue and read at a failure. Lock-guarded so the main-thread failure paths read it
/// synchronously; no per-line main-queue hop (C-8). r1 P3: only main-stream evidence is kept:
/// subtitle-side modules and external subtitle fetches are dropped at append, and `clear()` runs
/// at `MPV_EVENT_START_FILE`, so a line from before the current load never classifies it.
nonisolated final class MPVLogRing: @unchecked Sendable {
    static let capacity = 16
    private let lock = NSLock()
    private var lines: [String] = []

    /// mpv module prefixes that only ever speak about subtitles / OSD.
    static let subtitlePrefixes: Set<String> = ["sub", "osd", "sd_ass", "sd_lavc", "sd_sub", "ass", "sub/ass", "subreader"]
    private static let subtitleExtensions = #"\.(srt|vtt|webvtt|ass|ssa|sub|ttml|dfxp|smi|sup)(\?|\b)"#

    /// False for a line about a subtitle (its module, an external-file load, a subtitle URL).
    static func isMainStreamEvidence(prefix: String, text: String) -> Bool {
        let p = prefix.lowercased()
        if subtitlePrefixes.contains(p) || p.hasPrefix("sub") || p.hasPrefix("sd_") { return false }
        let lower = text.lowercased()
        if lower.contains("external file") || lower.contains("subtitle") { return false }
        if lower.range(of: subtitleExtensions, options: .regularExpression) != nil { return false }
        return true
    }

    func append(prefix: String, text: String) {
        guard Self.isMainStreamEvidence(prefix: prefix, text: text) else { return }
        append("\(prefix): \(text)")
    }

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
        lock.unlock()
    }

    /// A new file load starts: nothing logged before it is evidence about it.
    func clear() { lock.lock(); lines.removeAll(); lock.unlock() }

    var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
