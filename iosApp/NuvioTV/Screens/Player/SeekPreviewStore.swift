import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes and decodes one preview frame for `SeekPreviewStore` (tests use a fake).
nonisolated protocol PreviewFrameCodec: Sendable {
    func encode(_ image: CGImage) -> Data?
    func decode(_ data: Data) -> CGImage?
}

/// JPEG through ImageIO, quality 0.6 (about 12–25 KB for a 320 × 180 frame).
nonisolated struct JPEGPreviewCodec: PreviewFrameCodec {
    static let quality = 0.6

    func encode(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let props = [kCGImageDestinationLossyCompressionQuality: Self.quality] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

/// What a store insert did (P3 merge rules).
nonisolated enum SeekPreviewInsertOutcome: String, Equatable, Sendable {
    /// A new entry.
    case stored
    /// A harvest frame replaced the entry within 1 s of it (either origin).
    case replaced
    /// A decoded frame landed within 1 s of an entry: nothing changed (a decoded frame never
    /// replaces anything).
    case keptExisting
    /// A decoded frame met a full store: nothing stored, nothing evicted.
    case rejectedFull
    /// Bad stamp, over-wide image, or the encode failed.
    case invalid
}

/// The store's state right after an operation, taken inside the actor (critique C1). The
/// controller applies it on main to the scheduler's mirror (`ThumbScheduler.Inputs.store`), to
/// `TransportBarModel.previewFrames` and to the Info row summary; nothing reads the actor
/// synchronously.
nonisolated struct SeekPreviewSnapshot: Equatable, Sendable {
    var count: Int
    var bytes: Int
    var harvest: Int
    var decode: Int
    /// Every stamp, sorted ascending, all origins.
    var stamps: [Double]
    /// A decoded frame would fit without eviction (entry cap, and the byte cap with room for one
    /// average-sized entry). The pre-warm stops with `storeFull` once this is false.
    var acceptsDecode: Bool
    /// `thumbnail(near:)`'s default tolerance at this moment.
    var tolerance: Double

    static let empty = SeekPreviewSnapshot(count: 0, bytes: 0, harvest: 0, decode: 0, stamps: [],
                                           acceptsDecode: true, tolerance: 10)
}

/// `insert`'s return value: the outcome plus the snapshot after it (C1).
nonisolated struct SeekPreviewInsertResult: Equatable, Sendable {
    let outcome: SeekPreviewInsertOutcome
    let snapshot: SeekPreviewSnapshot
}

/// The seek-preview thumbnail store (P2, merge rules P3): small frames kept in memory for the life
/// of the player controller. No disk, no sync.
///
/// Two origins (P3): `harvest` frames are the ones the viewer played (P2, saved from the mpv
/// decode); `decode` frames come from the keyframe thumbnailer for ground not watched yet.
/// - A harvest frame within 1 s of any entry replaces it; a decoded frame within 1 s of any entry
///   is dropped (`keptExisting`). Played ground converges on the frames the viewer saw.
/// - A harvest insert over a cap evicts decoded frames first, the one with the smallest gap to
///   its neighbours (oldest on ties, critique C17), so the coarse coverage survives; only when no
///   decoded frame is left does it evict the oldest-inserted harvest frame (the P2 rule).
/// - A decoded insert never evicts: over a cap it is `rejectedFull`. The entry cap is checked
///   before the JPEG encode, so a rejected decode never pays it.
/// - Lookups do not refresh recency. Harvest-only mode keeps the P2 caps (200 / 6 MB, about the
///   last 33 minutes at one frame per 10 s); decode mode uses 800 / 16 MB.
actor SeekPreviewStore {
    static let defaultMaxEntries = 200
    static let defaultMaxBytes = 6 * 1024 * 1024
    /// Decode mode (P3 decision 8): harvest + decoded frames together.
    static let decodeMaxEntries = 800
    static let decodeMaxBytes = 16 * 1024 * 1024
    static let targetWidth = 320
    /// Two frames this close are the same picture (merge window).
    static let mergeWindowSec = 1.0

    /// The caps for a mode: decode mode grows them, the others keep P2's.
    nonisolated static func caps(for mode: SeekPreviewMode) -> (maxEntries: Int, maxBytes: Int) {
        mode.allowsDecode ? (decodeMaxEntries, decodeMaxBytes) : (defaultMaxEntries, defaultMaxBytes)
    }

    private struct Entry {
        let sec: Double
        let jpeg: Data
        let seq: UInt64
        let origin: PreviewFrameOrigin
    }

    let streamKey: String
    private let codec: PreviewFrameCodec
    private var maxEntries: Int
    private var maxBytes: Int
    private var entries: [Entry] = []          // sorted by `sec`
    private var nextSeq: UInt64 = 0
    private var bytes = 0
    private var lastDecoded: (seq: UInt64, image: CGImage)?
    /// The thumbnailer's median keyframe gap; folds the GOP into the lookup tolerance.
    private var keyframeSpacing: Double?

    init(streamKey: String, codec: PreviewFrameCodec = JPEGPreviewCodec(),
         maxEntries: Int = defaultMaxEntries, maxBytes: Int = defaultMaxBytes) {
        self.streamKey = streamKey
        self.codec = codec
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
    }

    var count: Int { entries.count }
    var byteCount: Int { bytes }
    var counts: (harvest: Int, decode: Int) {
        let h = entries.reduce(0) { $0 + ($1.origin == .harvest ? 1 : 0) }
        return (h, entries.count - h)
    }

    /// A decoded frame would fit without eviction: under the entry cap, and the bytes leave room
    /// for one average-sized entry (the real size is known only after the encode).
    var acceptsDecode: Bool {
        guard entries.count < maxEntries else { return false }
        let average = entries.isEmpty ? 0 : bytes / entries.count
        return bytes + average <= maxBytes
    }

    /// Changes the caps (decode mode, or a test). Lowering them evicts by the harvest-insert rule.
    @discardableResult
    func setCaps(maxEntries: Int, maxBytes: Int) -> SeekPreviewSnapshot {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
        evictOverCaps()
        return snapshot()
    }

    /// The median keyframe gap of the file (nil = unknown). Raises the lookup tolerance floor to
    /// one GOP, still capped at 30 s.
    @discardableResult
    func setKeyframeSpacing(_ sec: Double?) -> SeekPreviewSnapshot {
        keyframeSpacing = sec.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return snapshot()
    }

    func stamps() -> [Double] { entries.map(\.sec) }

    func snapshot() -> SeekPreviewSnapshot {
        let c = counts
        return SeekPreviewSnapshot(count: entries.count, bytes: bytes, harvest: c.harvest, decode: c.decode,
                                   stamps: stamps(), acceptsDecode: acceptsDecode, tolerance: defaultTolerance())
    }

    /// Inserts by the merge rules above; returns the outcome and the snapshot after it.
    @discardableResult
    func insert(_ image: CGImage, at sec: Double, origin: PreviewFrameOrigin = .harvest) -> SeekPreviewInsertResult {
        func done(_ o: SeekPreviewInsertOutcome) -> SeekPreviewInsertResult { .init(outcome: o, snapshot: snapshot()) }
        guard sec.isFinite, sec >= 0, image.width <= Self.targetWidth else { return done(.invalid) }
        let near = nearestIndex(to: sec).flatMap { abs(entries[$0].sec - sec) <= Self.mergeWindowSec ? $0 : nil }
        switch origin {
        case .decode:
            if near != nil { return done(.keptExisting) }
            guard entries.count < maxEntries else { return done(.rejectedFull) }   // before the encode
            guard let jpeg = codec.encode(image) else { return done(.invalid) }
            guard bytes + jpeg.count <= maxBytes else { return done(.rejectedFull) }
            add(Entry(sec: sec, jpeg: jpeg, seq: takeSeq(), origin: .decode))
            return done(.stored)
        case .harvest:
            guard let jpeg = codec.encode(image) else { return done(.invalid) }
            var outcome = SeekPreviewInsertOutcome.stored
            if let i = near {
                remove(at: i)
                outcome = .replaced
            }
            add(Entry(sec: sec, jpeg: jpeg, seq: takeSeq(), origin: .harvest))
            evictOverCaps()
            return done(outcome)
        }
    }

    /// `SeekPreviewSource`: the default tolerance.
    func thumbnail(near sec: Double) -> CGImage? { match(near: sec, tolerance: nil)?.image }

    /// The entry nearest `sec` (ties go to the earlier one), or nil when it is further than
    /// `tolerance` (default: `defaultTolerance()`).
    func thumbnail(near sec: Double, tolerance: Double?) -> CGImage? { match(near: sec, tolerance: tolerance)?.image }

    /// `SeekPreviewSource` (P3): the frame, its stamp and its origin.
    func match(near sec: Double) -> SeekPreviewMatch? { match(near: sec, tolerance: nil) }

    func match(near sec: Double, tolerance: Double?) -> SeekPreviewMatch? {
        guard sec.isFinite, let i = nearestIndex(to: sec) else { return nil }
        let tol = tolerance ?? defaultTolerance()
        let e = entries[i]
        guard abs(e.sec - sec) <= tol else { return nil }
        if let cached = lastDecoded, cached.seq == e.seq {
            return SeekPreviewMatch(image: cached.image, sec: e.sec, origin: e.origin)
        }
        guard let image = codec.decode(e.jpeg) else { return nil }
        lastDecoded = (e.seq, image)
        return SeekPreviewMatch(image: image, sec: e.sec, origin: e.origin)
    }

    /// `min(max(sampleSpacing, keyframeSpacing, 5), 30)`: decoded frames sit on a keyframe up to
    /// one GOP before the requested time, so the GOP raises the floor (the plan's "±GOP").
    func defaultTolerance() -> Double {
        min(max(sampleSpacing(), keyframeSpacing ?? 0, 5), 30)
    }

    /// Median of the gaps between consecutive stamps, counting only gaps ≤ 60 s (a seek leaves a
    /// hole that is not spacing); 10 when fewer than two such gaps exist. All origins.
    func sampleSpacing() -> Double {
        guard entries.count >= 3 else { return 10 }
        var gaps: [Double] = []
        for i in 1..<entries.count {
            let g = entries[i].sec - entries[i - 1].sec
            if g <= 60 { gaps.append(g) }
        }
        guard gaps.count >= 2 else { return 10 }
        gaps.sort()
        let mid = gaps.count / 2
        return gaps.count % 2 == 1 ? gaps[mid] : (gaps[mid - 1] + gaps[mid]) / 2
    }

    /// Runs of stamps whose gaps are ≤ 2 × the sample spacing; a lone stamp is `s...s`.
    func coverage() -> [ClosedRange<Double>] {
        guard let first = entries.first else { return [] }
        let join = 2 * sampleSpacing()
        var out: [ClosedRange<Double>] = []
        var lo = first.sec, hi = first.sec
        for e in entries.dropFirst() {
            if e.sec - hi <= join { hi = e.sec } else { out.append(lo...hi); lo = e.sec; hi = e.sec }
        }
        out.append(lo...hi)
        return out
    }

    @discardableResult
    func removeAll() -> SeekPreviewSnapshot {
        entries.removeAll()
        bytes = 0
        lastDecoded = nil
        return snapshot()
    }

    // MARK: - Private

    private func takeSeq() -> UInt64 {
        nextSeq &+= 1
        return nextSeq
    }

    private func add(_ e: Entry) {
        entries.insert(e, at: insertionIndex(for: e.sec))
        bytes += e.jpeg.count
    }

    private func remove(at i: Int) {
        invalidateDecode(entries[i].seq)
        bytes -= entries[i].jpeg.count
        entries.remove(at: i)
    }

    /// While over a cap: the densest decoded entry, else the oldest-inserted harvest entry.
    private func evictOverCaps() {
        while entries.count > maxEntries || bytes > maxBytes {
            guard let victim = densestDecodeIndex()
                    ?? entries.indices.min(by: { entries[$0].seq < entries[$1].seq }) else { break }
            remove(at: victim)
        }
    }

    /// The decoded entry with the smallest gap to its nearer neighbour (any origin); a lone entry
    /// counts as infinitely far. Ties go to the oldest inserted (C17).
    private func densestDecodeIndex() -> Int? {
        var best: (i: Int, gap: Double, seq: UInt64)?
        for i in entries.indices where entries[i].origin == .decode {
            let prev = i > 0 ? entries[i].sec - entries[i - 1].sec : .infinity
            let next = i + 1 < entries.count ? entries[i + 1].sec - entries[i].sec : .infinity
            let gap = min(prev, next)
            if let b = best, gap > b.gap || (gap == b.gap && entries[i].seq > b.seq) { continue }
            best = (i, gap, entries[i].seq)
        }
        return best?.i
    }

    private func invalidateDecode(_ seq: UInt64) {
        if lastDecoded?.seq == seq { lastDecoded = nil }
    }

    /// First index whose `sec` is ≥ `sec`.
    private func insertionIndex(for sec: Double) -> Int {
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].sec < sec { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func nearestIndex(to sec: Double) -> Int? {
        guard !entries.isEmpty else { return nil }
        let i = insertionIndex(for: sec)
        if i == 0 { return 0 }
        if i == entries.count { return entries.count - 1 }
        // Tie goes to the earlier entry.
        return (sec - entries[i - 1].sec) <= (entries[i].sec - sec) ? i - 1 : i
    }
}

extension SeekPreviewStore: SeekPreviewSource {}

/// One decoded frame copied out of `screenshot-raw` (no subtitles, no OSD).
nonisolated struct MPVRawFrame: Sendable {
    let width: Int
    let height: Int
    let stride: Int
    let format: String
    let bytes: Data
}

/// Turns a raw mpv frame into a store-sized thumbnail. Pure; runs off the main thread.
nonisolated enum PreviewFrameScaler {
    static func bitmapInfo(for format: String) -> CGBitmapInfo? {
        switch format {
        case "bgr0":
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        case "bgra":
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        case "rgba":
            return CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        default:
            return nil
        }
    }

    static func targetHeight(width: Int, sourceWidth: Int, sourceHeight: Int) -> Int {
        guard sourceWidth > 0 else { return 2 }
        return max(2, Int((Double(width) * Double(sourceHeight) / Double(sourceWidth)).rounded()))
    }

    static func makeThumbnail(_ f: MPVRawFrame, width: Int = SeekPreviewStore.targetWidth) -> CGImage? {
        guard f.width > 0, f.height > 0, let info = bitmapInfo(for: f.format),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: f.bytes as CFData),
              let source = CGImage(width: f.width, height: f.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: f.stride, space: space, bitmapInfo: info, provider: provider,
                                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let w = min(width, f.width)
        let h = targetHeight(width: w, sourceWidth: f.width, sourceHeight: f.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

/// The process's physical footprint (what jetsam counts), for the Info tab's Seek Previews row.
nonisolated enum ProcessMemory {
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1_048_576)
    }
}
