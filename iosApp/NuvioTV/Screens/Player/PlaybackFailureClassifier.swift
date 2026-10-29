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
    /// r2 P3: `extract extradata` and `video stream` are remux setup steps. `no video stream` is our
    /// limit too: the remux needs a video track, but mpv plays an audio-only item, so the link is fine.
    static let engineInternalStages: Set<String> = [
        "no segment map", "no usable keyframe index", "server bind failed", "alloc input ctx",
        "packet_alloc", "output context", "audio output context", "audio transcoder init",
        "extract extradata", "video stream", "no video stream",
    ]
    static func isEngineInternalStage(_ stage: String) -> Bool {
        engineInternalStages.contains(stage) || stage.hasPrefix("DV P7 converter init")
            // Wave 3 (BUG-199, review r2 P3-3): the video grid's net cap is our own limit, never
            // the source's; a stale FFmpeg code must not relabel it.
            || stage.hasPrefix("grid net cap")
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
/// synchronously; no per-line main-queue hop (C-8). Only main-stream evidence is kept, and
/// `clear()` runs at `MPV_EVENT_START_FILE`, so a line from before the current load never
/// classifies it.
///
/// r2 P3: a line is judged by where it came from, not by words in its URL. mpv hands every log
/// message a MODULE prefix (`sub`, `sd_ass`, `osd`, `cplayer`, `stream`, `ffmpeg`,
/// `ffmpeg/demuxer`, …) and FFmpeg's own lines carry their context name at the start of the text
/// (`srt: Dropping 4 duplicated subtitle events`, `tls: Error decoding the received TLS packet.`,
/// `https: Error reading HTTP response: …` in the 10-15 device logs). Subtitle modules and subtitle
/// codec/demuxer contexts are dropped; protocol lines (`tcp`/`tls`/`https`) are kept, whatever the
/// main-stream URL is called (`Movie.2024.MULTi.SUB.1080p.mkv`, a `x.sub.example` host). The
/// URL-less protocol lines of an in-core `sub-add <http url>` are dropped by the player's
/// attribution window (`subtitleLoadBegan` / `subtitleLoadDrained`): only protocol contexts
/// (`protocolContexts`), so a main-stream `ffmpeg/demuxer` line drained there is kept.
nonisolated final class MPVLogRing: @unchecked Sendable {
    static let capacity = 16
    private let lock = NSLock()
    private var lines: [String] = []
    /// Set while an in-core `sub-add` is in flight: from just before the player issues it until it
    /// has drained the lines buffered by the time the command replied. The command now runs
    /// asynchronously, one at a time (`MPVSubtitleSideLoadQueue`), so ordinary wakeup drains inside
    /// the window are attributed the same way; the old synchronous command swallowed the same lines.
    private var attributingSubtitleLoad = false

    /// mpv module prefixes that only ever speak about subtitles / OSD.
    static let subtitlePrefixes: Set<String> = ["sub", "osd", "sd_ass", "sd_lavc", "sd_sub", "ass", "sub/ass", "subreader"]
    /// FFmpeg context names (the `name:` that starts the text) of subtitle demuxers and decoders.
    static let subtitleContexts: Set<String> = [
        "srt", "subrip", "ass", "ssa", "webvtt", "vtt", "mov_text", "ttml", "sami", "microdvd", "subviewer",
        "subviewer1", "mpl2", "mpsub", "jacosub", "realtext", "stl", "vplayer", "pjs", "aqtitle", "lrc", "scc",
        "dvdsub", "dvd_subtitle", "dvbsub", "dvb_subtitle", "pgssub", "hdmv_pgs_subtitle", "sup", "libzvbi_teletextdec",
        "text", "eia_608", "cc_dec", "dfxp",
    ]
    /// FFmpeg protocol context names: the only lines the `sub-add` attribution window drops.
    static let protocolContexts: Set<String> = ["tcp", "tls", "http", "https", "crypto"]
    /// A subtitle file URL: the extension ends the URL path (query, whitespace, end, or a trailing
    /// period / comma / bracket before whitespace or the end). Not `.SUB.` inside a release name.
    private static let subtitleURLPattern =
        #"\.(srt|vtt|webvtt|ass|ssa|sub|ttml|dfxp|smi|sup)(\?\S*)?([.,;)\]]*)(\s|$)"#

    /// The FFmpeg context name that starts `text` (`"srt"` for `srt: Dropping …`), lowercased.
    static func leadingContext(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = text[..<colon]
        guard !name.isEmpty, name.count <= 32,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "," }) else { return nil }
        return name.lowercased()
    }

    /// False for a line about a subtitle: its mpv module, its FFmpeg subtitle context, an
    /// external-file load, or a subtitle file URL.
    static func isMainStreamEvidence(prefix: String, text: String) -> Bool {
        let p = prefix.lowercased()
        if subtitlePrefixes.contains(p) || p.hasPrefix("sub") || p.hasPrefix("sd_") { return false }
        if let context = leadingContext(of: text), subtitleContexts.contains(context) { return false }
        let lower = text.lowercased()
        if lower.contains("external file") { return false }
        if lower.range(of: subtitleURLPattern, options: .regularExpression) != nil { return false }
        return true
    }

    func append(prefix: String, text: String) {
        guard Self.isMainStreamEvidence(prefix: prefix, text: text) else { return }
        lock.lock()
        let attributing = attributingSubtitleLoad
        lock.unlock()
        // r3 P3: inside the window only protocol lines are the subtitle fetch's; a demuxer or
        // decoder line there is still the stream's.
        let dropAsSubtitleLoad = attributing && prefix.lowercased().hasPrefix("ffmpeg")
            && Self.leadingContext(of: text).map(Self.protocolContexts.contains) == true
        guard !dropAsSubtitleLoad else { return }
        append("\(prefix): \(text)")
    }

    /// Event queue: an in-core `sub-add` is about to run (the player drains the queue first, so
    /// earlier lines are already in). Until `subtitleLoadDrained()`, FFmpeg protocol lines (its
    /// URL-less `tcp:` / `tls:` / `https:` lines) are the subtitle load's, not the stream's. A
    /// main-stream protocol line logged while the command is in flight is dropped too.
    func subtitleLoadBegan() { lock.lock(); attributingSubtitleLoad = true; lock.unlock() }
    /// Event queue: the lines buffered during the `sub-add` have been drained.
    func subtitleLoadDrained() { lock.lock(); attributingSubtitleLoad = false; lock.unlock() }

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
