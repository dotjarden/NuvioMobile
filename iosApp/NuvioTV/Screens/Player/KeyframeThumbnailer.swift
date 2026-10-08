import CoreGraphics
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswscale

/// The FFmpeg surface the P3 keyframe thumbnailer relies on (critique C11): `Libswscale` imports
/// in this MPVKit build (swscale 9, FFmpeg 8.1). `sws_scale_frame` is deliberately not used in P3:
/// its colour-managed path could tone-map a second time on top of `HDRThumbnailToneMap`.
nonisolated enum ThumbFFmpegSurface {
    /// `swscale <major>.<minor>.<micro> test_transfer(pq,in)=<n>`, logged once per process.
    static let versionLine: String = {
        let v = swscale_version()
        let pq = sws_test_transfer(AVCOL_TRC_SMPTE2084, 0)
        return "swscale \(v >> 16).\((v >> 8) & 0xFF).\(v & 0xFF) test_transfer(pq,in)=\(pq)"
    }()
}

// MARK: - Results

/// What `open()` learned about the file.
nonisolated struct ThumbFileFacts: Sendable {
    let container: String
    let durationSec: Double
    let sizeBytes: Int64?
    /// Keyframe times in seconds on mpv's timeline (relative to the file's start), sorted.
    let keyframeIndex: [Double]
    /// From the stream header; the frame path routes on the decoded frame's own colour fields (C4).
    let hdr: HDRFormat
    let openMs: Double
}

nonisolated enum ThumbOpenResult: Sendable {
    case ready(ThumbFileFacts)
    case refused(ThumbStopReason)
}

nonisolated enum ThumbFrameResult: @unchecked Sendable {
    /// `keyframeSec` on mpv's timeline; `tookMs` the whole call; `decodeMs` send → receive;
    /// `toneMapMs` the HDR tone map (0 for SDR); `bytes` what avio consumed for this frame.
    case frame(CGImage, keyframeSec: Double, tookMs: Double, decodeMs: Double, toneMapMs: Double, bytes: Int64)
    /// nil = transient (this slot only); non-nil = stop the file.
    case failed(ThumbStopReason?)
    /// The thumbnailer was closed (or never opened).
    case aborted
}

// MARK: - Interrupt gate

/// Shared with FFmpeg's `AVIOInterruptCB`: `aborted` (close) or a passed per-call deadline makes
/// the next poll return 1. Owned by the thumbnailer, which outlives its format context (the
/// context is closed on the thumbnailer's queue or in its `deinit`), so the callback's opaque
/// pointer is unretained.
nonisolated final class ThumbInterruptGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _aborted = false
    private var _deadline: TimeInterval = .infinity

    var aborted: Bool { lock.lock(); defer { lock.unlock() }; return _aborted }
    func abort() { lock.lock(); _aborted = true; lock.unlock() }
    func arm(seconds: Double) {
        lock.lock(); _deadline = ProcessInfo.processInfo.systemUptime + seconds; lock.unlock()
    }
    func disarm() { lock.lock(); _deadline = .infinity; lock.unlock() }
    var deadlinePassed: Bool {
        lock.lock(); defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime >= _deadline
    }
    var shouldInterrupt: Bool {
        lock.lock(); defer { lock.unlock() }
        return _aborted || ProcessInfo.processInfo.systemUptime >= _deadline
    }
}

nonisolated func thumbShouldInterrupt(_ opaque: UnsafeMutableRawPointer?) -> Int32 {
    guard let opaque else { return 0 }
    return Unmanaged<ThumbInterruptGate>.fromOpaque(opaque).takeUnretainedValue().shouldInterrupt ? 1 : 0
}

// MARK: - Thumbnailer

/// Player P3 (mpv engine): decodes one keyframe at a time from the playing file over a second,
/// lazily opened avformat input, scaled to the seek-preview store's 320 px, for ground the viewer
/// has not played yet. Spec `docs/research/player-p3-spec-thumbnailer.md` §2 with critique C3, C4,
/// C6–C11, C13.
///
/// Threading: every FFmpeg handle lives and dies on `queue` (never `eventQueue`, never main).
/// `open()` and `frame(at:urgent:)` hop onto it; `close()` returns at once from any thread.
///
/// Lifetime (C13): this object holds no reference to the controller, the mpv handle or any UI
/// state. The controller drops it after `close()`; a block already running on `queue` keeps it
/// alive until that block returns, so it can outlive the controller by one in-flight call. That
/// window is NOT bounded by the interrupt: a `getaddrinfo` DNS lookup is not interrupt-polled, and
/// a 4K software decode plus scale cannot be interrupted, so it lasts until the current lookup or
/// decode returns, with the decoder's frame pools (about 25–40 MB at 4K) alive meanwhile. Blocking
/// on a semaphore instead was rejected (a main-thread stall on every exit).
///
/// Network (C6): the same URL and addon headers mpv sends (this is the media host, so the
/// credentials go too), `user_agent` = mpv's when the headers carry none, `request_size` 2 MB so
/// every read is a bounded range, `multiple_requests` 0 so the connection closes with the
/// response: between frames this holds no connection to the host at all. avformat opens a new
/// TCP (and TLS) connection per seek. Never logs the URL or the headers.
nonisolated final class KeyframeThumbnailer: @unchecked Sendable {
    static let requestSizeBytes = 2 * 1024 * 1024
    /// Per call: open, then each frame (urgent = a scrub the viewer is waiting on).
    static let openDeadlineSec = 10.0
    static let urgentFrameDeadlineSec = 3.0
    static let frameDeadlineSec = 6.0
    /// Read budget for finding the key packet after a seek: video packets, then bytes.
    static let maxPacketsWithoutKey = 64
    static let maxBytesWithoutKey: Int64 = 8 * 1024 * 1024
    /// Three deadline expiries in a row stop the file (`stalled`).
    static let maxConsecutiveStalls = 3

    private let url: URL
    private let headers: [String: String]
    private let queue = DispatchQueue(label: "player.thumbs", qos: .utility)
    private let gate = ThumbInterruptGate()
    private let bytesLock = NSLock()
    private var _bytesRead: Int64 = 0

    // `queue` only (or `deinit`, when no block can be pending).
    private var closed = false
    private var openResult: ThumbOpenResult?
    private var fmt: UnsafeMutablePointer<AVFormatContext>?
    private var videoIndex: Int32 = -1
    private var timeBase = AVRational(num: 1, den: 1000)
    private var startSec: Double = 0
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var sws: UnsafeMutablePointer<SwsContext>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var avFrame: UnsafeMutablePointer<AVFrame>?
    private var consecutiveStalls = 0
    private var parTrc: Int32 = HDRThumbnailToneMap.avcolTrcUnspecified
    private var parPrimaries: Int32 = HDRThumbnailToneMap.avcolPriUnspecified

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    /// C13 (b): a thumbnailer dropped without `close()` still frees its native state. Every queue
    /// block retains `self`, so none can be pending here and nothing races this.
    deinit {
        if !closed { teardownNative() }
    }

    /// Bytes avio consumed (open included). Any thread.
    var bytesRead: Int64 {
        bytesLock.lock(); defer { bytesLock.unlock() }
        return _bytesRead
    }

    /// Opens once; later calls return the first result.
    func open() async -> ThumbOpenResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ThumbOpenResult, Never>) in
            queue.async {
                cont.resume(returning: self.openOnQueue())
            }
        }
    }

    /// One keyframe at or before `sec`.
    func frame(at sec: Double, urgent: Bool) async -> ThumbFrameResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ThumbFrameResult, Never>) in
            queue.async(qos: urgent ? .userInitiated : .utility, flags: urgent ? .enforceQoS : []) {
                cont.resume(returning: self.frameOnQueue(at: sec, urgent: urgent))
            }
        }
    }

    /// Frees the decoder and scaler (a 4K decoder's frame pools), keeps the demuxer.
    func releaseDecoder() {
        queue.async {
            guard !self.closed else { return }
            self.freeDecoder()
        }
    }

    /// Idempotent, any thread, returns at once: the interrupt fires on avformat's next poll, then
    /// the native state is torn down on `queue` after any in-flight call returns.
    func close() {
        gate.abort()
        queue.async {
            guard !self.closed else { return }
            self.teardownNative()
        }
    }

    // MARK: Open (queue)

    private func openOnQueue() -> ThumbOpenResult {
        if let openResult { return openResult }
        let r = doOpen()
        openResult = r
        return r
    }

    private func doOpen() -> ThumbOpenResult {
        guard !closed, !gate.aborted else { return .refused(.modeOff) }
        let t0 = DispatchTime.now().uptimeNanoseconds
        #if DEBUG
        Self.logSurfaceOnce()
        #endif
        MediaProbeNetwork.ensureInit()
        guard let allocated = avformat_alloc_context() else { return refuse(.openFailed) }
        allocated.pointee.interrupt_callback = AVIOInterruptCB(
            callback: thumbShouldInterrupt, opaque: Unmanaged.passUnretained(gate).toOpaque())

        var opts: OpaquePointer?
        defer { av_dict_free(&opts) }
        if !headers.isEmpty {
            av_dict_set(&opts, "headers", MediaProbe.ffmpegHeaderBlock(headers), 0)
        }
        if !headers.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            av_dict_set(&opts, "user_agent", "libmpv", 0)        // what mpv's own requests carry
        }
        av_dict_set(&opts, "request_size", String(Self.requestSizeBytes), 0)
        av_dict_set(&opts, "multiple_requests", "0", 0)
        av_dict_set(&opts, "rw_timeout", "5000000", 0)
        av_dict_set(&opts, "timeout", "5000000", 0)
        av_dict_set(&opts, "reconnect", "0", 0)
        av_dict_set(&opts, "probesize", "2000000", 0)
        av_dict_set(&opts, "analyzeduration", "1000000", 0)
        av_dict_set(&opts, "fflags", "+nobuffer", 0)

        gate.arm(seconds: Self.openDeadlineSec)
        defer { gate.disarm() }
        var ctx: UnsafeMutablePointer<AVFormatContext>? = allocated
        // On failure avformat_open_input frees and nils the context it was given.
        let rc = avformat_open_input(&ctx, url.absoluteString, nil, &opts)
        guard rc == 0, let ctx else {
            if gate.aborted { return .refused(.modeOff) }
            return refuse(Self.isHTTPError(rc) ? .httpRefused : .openFailed)
        }
        fmt = ctx
        noteBytes()

        let container = ctx.pointee.iformat.flatMap { $0.pointee.name }.map { String(cString: $0) } ?? ""
        guard container.contains("matroska") || container.contains("mov") else { return refuse(.container) }

        // The first real video stream (attached pictures excluded, `MediaProbe`'s rule).
        let attachedPic: Int32 = 1 << 10                             // AV_DISPOSITION_ATTACHED_PIC
        var v: Int32 = -1
        for i in 0..<Int32(ctx.pointee.nb_streams) {
            guard let s = ctx.pointee.streams[Int(i)], let par = s.pointee.codecpar else { continue }
            if par.pointee.codec_type == AVMEDIA_TYPE_VIDEO, s.pointee.disposition & attachedPic == 0 { v = i; break }
        }
        guard v >= 0, let vs = ctx.pointee.streams[Int(v)], let par = vs.pointee.codecpar else {
            return refuse(.container)
        }
        videoIndex = v
        // C8: the demuxer drops every other stream's blocks, so the key-packet budget counts video.
        for i in 0..<Int(ctx.pointee.nb_streams) where Int32(i) != v {
            ctx.pointee.streams[i]?.pointee.discard = AVDISCARD_ALL
        }

        // MKV and MP4 headers normally carry the size and the parameter sets; probe only if not.
        if par.pointee.width <= 0 || par.pointee.extradata_size <= 0 {
            guard avformat_find_stream_info(ctx, nil) >= 0 else {
                if gate.aborted { return .refused(.modeOff) }
                return refuse(.openFailed)
            }
            noteBytes()
        }

        // Dolby Vision profile 5 (and any config with no compatible base layer): the base layer is
        // IPTPQc2 and decodes to wrong colours. Profiles 7 and 8 decode their base layer.
        if let dv = MediaProbe.dolbyVision(par), dv.compatId == 0 { return refuse(.dvProfile5) }

        timeBase = vs.pointee.time_base
        guard timeBase.num > 0, timeBase.den > 0 else { return refuse(.openFailed) }
        // C10: mpv rebases `time-pos` on the demuxer's start time (`fmt.start_time`, min over the
        // streams), then the video stream's, then 0.
        let noPTS = Int64.min
        if ctx.pointee.start_time != noPTS {
            startSec = Double(ctx.pointee.start_time) / 1_000_000
        } else if vs.pointee.start_time != noPTS {
            startSec = Double(vs.pointee.start_time) * Double(timeBase.num) / Double(timeBase.den)
        }
        let durationSec = ctx.pointee.duration > 0 ? Double(ctx.pointee.duration) / 1_000_000 : 0
        parTrc = Int32(truncatingIfNeeded: par.pointee.color_trc.rawValue)
        parPrimaries = Int32(truncatingIfNeeded: par.pointee.color_primaries.rawValue)

        // C3: `RemuxSession.buildSegmentMap`'s priming rule (RemuxSession.swift, "Prime whenever
        // the index is too sparse"): find_stream_info can leave 3–6 entries on high-bitrate
        // remuxes, and tail-loaded Cues (mkvmerge's default, and ffmpeg's muxer, which wrote the
        // smoke fixture) load only on a seek. Copied, not shared, so the remuxer stays untouched.
        var index = keyframeSeconds(vs)
        let minUsable = durationSec > 0 ? Int(durationSec / 30) + 1 : 2
        if index.count < max(2, minUsable), ctx.pointee.duration > 0 {
            // stream_index -1: the timestamp is in AV_TIME_BASE, matching `duration`.
            av_seek_frame(ctx, -1, ctx.pointee.duration, AVSEEK_FLAG_BACKWARD)
            let primed = keyframeSeconds(vs)
            if primed.count > index.count { index = primed }
            noteBytes()
        }
        if gate.aborted { return .refused(.modeOff) }
        guard index.count >= max(2, minUsable) else { return refuse(.noIndex) }

        let size = ctx.pointee.pb.map { avio_size($0) } ?? -1
        let facts = ThumbFileFacts(
            container: container, durationSec: durationSec, sizeBytes: size > 0 ? size : nil,
            keyframeIndex: index, hdr: MediaProbe.hdrFormat(par.pointee.color_trc),
            openMs: Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        #if DEBUG
        let budget = ThumbScheduler.byteBudget(fileSize: facts.sizeBytes)
        NSLog("%@", String(format: "[Thumbs] open took=%.0fms container=%@ index=%d size=%.0fMB budget=%.1fMB hdr=%@ read=%.0fKB",
                           facts.openMs, container, index.count, Double(size > 0 ? size : 0) / 1_048_576,
                           Double(budget) / 1_048_576, facts.hdr.rawValue, Double(bytesRead) / 1024))
        #endif
        return .ready(facts)
    }

    private func refuse(_ reason: ThumbStopReason) -> ThumbOpenResult {
        #if DEBUG
        NSLog("%@", "[Thumbs] off reason=\(reason.rawValue)")
        #endif
        return .refused(reason)
    }

    /// The video stream's keyframe entries, in seconds on mpv's timeline, sorted.
    private func keyframeSeconds(_ vs: UnsafeMutablePointer<AVStream>) -> [Double] {
        let count = avformat_index_get_entries_count(vs)
        var out: [Double] = []
        out.reserveCapacity(Int(max(count, 0)))
        let tb = Double(timeBase.num) / Double(timeBase.den)
        for i in 0..<count {
            guard let e = avformat_index_get_entry(vs, i) else { continue }
            let entry = e.pointee
            guard entry.timestamp != Int64.min, (entry.flags & AVINDEX_KEYFRAME) != 0 else { continue }
            out.append(Double(entry.timestamp) * tb - startSec)
        }
        return out.sorted()
    }

    // MARK: Frame (queue)

    private func frameOnQueue(at sec: Double, urgent: Bool) -> ThumbFrameResult {
        guard !closed, !gate.aborted, case .ready = openResult, let fmt, videoIndex >= 0,
              let vs = fmt.pointee.streams[Int(videoIndex)], let par = vs.pointee.codecpar else { return .aborted }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let bytes0 = currentAvioBytes()
        gate.arm(seconds: urgent ? Self.urgentFrameDeadlineSec : Self.frameDeadlineSec)
        defer { gate.disarm(); noteBytes() }

        if packet == nil { packet = av_packet_alloc() }
        if avFrame == nil { avFrame = av_frame_alloc() }
        guard let pkt = packet, let frame = avFrame else { return .failed(nil) }

        let tb = Double(timeBase.num) / Double(timeBase.den)
        let ts = Int64(((max(sec, 0) + startSec) / tb).rounded(.down))
        let seekRC = av_seek_frame(fmt, videoIndex, ts, AVSEEK_FLAG_BACKWARD)
        if seekRC < 0 { return readFailure(seekRC) }

        // The first video key packet after the seek (matroskadec lands on the cue at or before
        // the target, C9). Other streams are discarded at the demuxer (C8).
        var videoPackets = 0
        var keyPTS = Int64.min
        while true {
            let r = av_read_frame(fmt, pkt)
            if r < 0 { return readFailure(r) }
            if pkt.pointee.stream_index != videoIndex { av_packet_unref(pkt); continue }
            if pkt.pointee.flags & AV_PKT_FLAG_KEY != 0 {
                keyPTS = pkt.pointee.pts != Int64.min ? pkt.pointee.pts : pkt.pointee.dts
                break
            }
            av_packet_unref(pkt)
            videoPackets += 1
            if videoPackets >= Self.maxPacketsWithoutKey || currentAvioBytes() - bytes0 >= Self.maxBytesWithoutKey {
                return .failed(nil)
            }
        }
        defer { av_packet_unref(pkt) }

        guard let dec = ensureDecoder(par: par, stream: vs) else { return .failed(.openFailed) }
        // One packet in, one frame out: send the key packet, drain, then flush so the decoder is
        // reusable for the next seek.
        let d0 = DispatchTime.now().uptimeNanoseconds
        var got = false
        if avcodec_send_packet(dec, pkt) >= 0 {
            _ = avcodec_send_packet(dec, nil)
            // Drain mode: the frame, or EOF / an error (no frame).
            got = avcodec_receive_frame(dec, frame) >= 0
        }
        avcodec_flush_buffers(dec)
        let decodeMs = Double(DispatchTime.now().uptimeNanoseconds - d0) / 1e6
        if gate.aborted { av_frame_unref(frame); return .aborted }
        guard got else { return .failed(nil) }
        defer { av_frame_unref(frame) }

        let best = frame.pointee.best_effort_timestamp
        let stampTicks = best != Int64.min ? best : keyPTS
        let keyframeSec = stampTicks != Int64.min ? Double(stampTicks) * tb - startSec : sec
        guard let scaled = scale(frame) else { return .failed(nil) }
        consecutiveStalls = 0
        noteBytes()
        let tookMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        return .frame(scaled.image, keyframeSec: keyframeSec, tookMs: tookMs, decodeMs: decodeMs,
                      toneMapMs: scaled.toneMapMs, bytes: max(currentAvioBytes() - bytes0, 0))
    }

    /// A failed seek or read: aborted, an HTTP refusal (stop the file, C7), a deadline expiry
    /// (three in a row stop the file), or a transient failure for this slot.
    private func readFailure(_ rc: Int32) -> ThumbFrameResult {
        if gate.aborted { return .aborted }
        if Self.isHTTPError(rc) { return .failed(.httpRefused) }
        if gate.deadlinePassed {
            consecutiveStalls += 1
            return consecutiveStalls >= Self.maxConsecutiveStalls ? .failed(.stalled) : .failed(nil)
        }
        return .failed(nil)
    }

    /// Lazy software decoder: two slice threads, fast flags, no loop filter.
    private func ensureDecoder(par: UnsafeMutablePointer<AVCodecParameters>,
                               stream: UnsafeMutablePointer<AVStream>) -> UnsafeMutablePointer<AVCodecContext>? {
        if let codecCtx { return codecCtx }
        guard let codec = avcodec_find_decoder(par.pointee.codec_id),
              let ctx = avcodec_alloc_context3(codec) else { return nil }
        guard avcodec_parameters_to_context(ctx, par) >= 0 else {
            var c: UnsafeMutablePointer<AVCodecContext>? = ctx; avcodec_free_context(&c); return nil
        }
        ctx.pointee.pkt_timebase = stream.pointee.time_base
        ctx.pointee.flags2 |= AV_CODEC_FLAG2_FAST
        // C9: an H.264 open-GOP I-frame without a recovery-point SEI is otherwise held back and
        // the drain returns nothing. HEVC CRA decodes standalone (no RASL picture is sent).
        if par.pointee.codec_id == AV_CODEC_ID_H264 { ctx.pointee.flags2 |= AV_CODEC_FLAG2_SHOW_ALL }
        ctx.pointee.skip_loop_filter = AVDISCARD_ALL
        // Never set `skip_frame`: with AVDISCARD_NONKEY on MKV the decoder swallows every packet
        // (Orivio handoff §7.9).
        ctx.pointee.thread_count = 2
        ctx.pointee.thread_type = FF_THREAD_SLICE
        guard avcodec_open2(ctx, codec, nil) >= 0 else {
            var c: UnsafeMutablePointer<AVCodecContext>? = ctx; avcodec_free_context(&c); return nil
        }
        codecCtx = ctx
        return ctx
    }

    // MARK: Scale (queue)

    /// To 320 px wide (display aspect). C4: the colour path comes from the decoded frame's own
    /// fields (falling back to the stream header only when the frame says unspecified); HDR (and
    /// any BT.2020 source) scales to RGB48 with BT.2020 coefficients set explicitly
    /// (`sws_getCachedContext` defaults to BT.601) and goes through `HDRThumbnailToneMap`; SDR
    /// scales straight to `bgr0`. `linesize[0]` of the destination is the row stride everywhere.
    private func scale(_ frame: UnsafeMutablePointer<AVFrame>) -> (image: CGImage, toneMapMs: Double)? {
        let srcW = Int(frame.pointee.width), srcH = Int(frame.pointee.height)
        guard srcW > 0, srcH > 0 else { return nil }
        let sar = frame.pointee.sample_aspect_ratio
        let displayW = sar.num > 0 && sar.den > 0 ? Double(srcW) * Double(sar.num) / Double(sar.den) : Double(srcW)
        let dstW = min(SeekPreviewStore.targetWidth, srcW)
        let dstH = PreviewFrameScaler.targetHeight(width: dstW, sourceWidth: Int(displayW.rounded()), sourceHeight: srcH)

        let color = HDRThumbnailToneMap.fromDecodedFrame(
            trc: Int32(truncatingIfNeeded: frame.pointee.color_trc.rawValue),
            primaries: Int32(truncatingIfNeeded: frame.pointee.color_primaries.rawValue),
            codecparTrc: parTrc, codecparPrimaries: parPrimaries)
        let wide = color.isHDR || color.primaries == .bt2020
        let dstFmt = wide ? AV_PIX_FMT_RGB48LE : AV_PIX_FMT_BGR0
        let bpp = wide ? 6 : 4
        let stride = (dstW * bpp + 63) & ~63

        let srcFmt = AVPixelFormat(rawValue: numericCast(frame.pointee.format))
        sws = sws_getCachedContext(sws, Int32(srcW), Int32(srcH), srcFmt, Int32(dstW), Int32(dstH), dstFmt,
                                   Int32(truncatingIfNeeded: SWS_BILINEAR.rawValue), nil, nil, nil)
        guard let swsCtx = sws else { return nil }

        // Source matrix: the frame's, else BT.2020 for wide sources, BT.709 for HD, BT.601 below.
        let spc = Int32(truncatingIfNeeded: frame.pointee.colorspace.rawValue)
        let srcMatrix: Int32
        switch spc {
        case 9, 10: srcMatrix = Int32(SWS_CS_BT2020)                  // AVCOL_SPC_BT2020_NCL / _CL
        case 1: srcMatrix = Int32(SWS_CS_ITU709)
        case 5, 6: srcMatrix = Int32(SWS_CS_ITU601)
        default: srcMatrix = wide ? Int32(SWS_CS_BT2020) : (srcW >= 1280 ? Int32(SWS_CS_ITU709) : Int32(SWS_CS_ITU601))
        }
        // Unspecified range reads as limited (video).
        let srcFull: Int32 = Int32(truncatingIfNeeded: frame.pointee.color_range.rawValue) == 2 ? 1 : 0   // AVCOL_RANGE_JPEG
        _ = sws_setColorspaceDetails(swsCtx, sws_getCoefficients(srcMatrix), srcFull,
                                     sws_getCoefficients(Int32(SWS_CS_DEFAULT)), 1, 0, 1 << 16, 1 << 16)

        var buffer = [UInt8](repeating: 0, count: stride * dstH)
        let d = frame.pointee.data
        let src: [UnsafePointer<UInt8>?] = [d.0, d.1, d.2, d.3].map { $0.map { UnsafePointer($0) } }
        let l = frame.pointee.linesize
        let srcStride: [Int32] = [l.0, l.1, l.2, l.3]
        let dstStride: [Int32] = [Int32(stride), 0, 0, 0]
        let rows: Int32 = buffer.withUnsafeMutableBufferPointer { out in
            let dst: [UnsafeMutablePointer<UInt8>?] = [out.baseAddress, nil, nil, nil]
            return sws_scale(swsCtx, src, srcStride, 0, Int32(srcH), dst, dstStride)
        }
        guard rows > 0 else { return nil }

        if wide {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let image = buffer.withUnsafeBytes {
                HDRThumbnailToneMap.apply(rgb48: $0.baseAddress!, width: dstW, height: dstH, bytesPerRow: stride,
                                          color: color, masteringMaxNits: masteringMaxNits(frame))
            }
            guard let image else { return nil }
            return (image, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(width: dstW, height: dstH, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: stride, space: space, bitmapInfo: info, provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return (image, 0)
    }

    /// The mastering display's peak from the frame's side data, when it carries one.
    private func masteringMaxNits(_ frame: UnsafeMutablePointer<AVFrame>) -> Double? {
        guard let sd = av_frame_get_side_data(frame, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA),
              let data = sd.pointee.data,
              Int(sd.pointee.size) >= MemoryLayout<AVMasteringDisplayMetadata>.size else { return nil }
        let md = UnsafeRawPointer(data).assumingMemoryBound(to: AVMasteringDisplayMetadata.self).pointee
        guard md.has_luminance != 0, md.max_luminance.den > 0 else { return nil }
        let nits = Double(md.max_luminance.num) / Double(md.max_luminance.den)
        return nits > 0 ? nits : nil
    }

    // MARK: Bytes and teardown (queue)

    private func currentAvioBytes() -> Int64 { fmt?.pointee.pb?.pointee.bytes_read ?? 0 }

    /// `AVIOContext.bytes_read` is cumulative for the input; with bounded ranges (C6) it is
    /// what came over the wire.
    private func noteBytes() {
        let b = currentAvioBytes()
        bytesLock.lock()
        if b > _bytesRead { _bytesRead = b }
        bytesLock.unlock()
    }

    private func freeDecoder() {
        if codecCtx != nil { avcodec_free_context(&codecCtx) }
        if let s = sws { sws_freeContext(s); sws = nil }
    }

    private func teardownNative() {
        closed = true
        freeDecoder()
        if packet != nil { av_packet_free(&packet) }
        if avFrame != nil { av_frame_free(&avFrame) }
        if fmt != nil { avformat_close_input(&fmt) }
    }

    // MARK: Helpers

    /// Any `AVERROR_HTTP_*` (FFERRTAG(0xF8, '4' or '5', …)).
    static func isHTTPError(_ rc: Int32) -> Bool {
        guard rc < 0 else { return false }
        let v = UInt32(bitPattern: -rc)
        let b0 = v & 0xFF, b1 = (v >> 8) & 0xFF
        return b0 == 0xF8 && (b1 == UInt32(UInt8(ascii: "4")) || b1 == UInt32(UInt8(ascii: "5")))
    }

    #if DEBUG
    private static let surfaceLogged: Void = {
        NSLog("%@", "[Thumbs] \(ThumbFFmpegSurface.versionLine)")
    }()
    static func logSurfaceOnce() { _ = surfaceLogged }
    #endif
}
