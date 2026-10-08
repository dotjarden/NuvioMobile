import Foundation

/// Trims one of the remuxer's fMP4 media segments (exactly `moof` + `mdat`, the boundary keyframe
/// as sample 0) down to a fragment holding only that first sample, for the `EXT-X-I-FRAMES-ONLY`
/// rendition `LocalHLSServer` serves as `iframe-NNNNN.m4s` (player P3 spike).
///
/// The `trun` is rewritten to `sample_count = 1` with the first entry kept, every enclosing box
/// size (`traf`, `moof`) shrinks by the dropped entries, `data_offset` (relative to the moof start
/// under `default_base_moof`) is recomputed, and the `mdat` carries the first sample's bytes only.
/// Pure: no I/O, no AVFoundation; a malformed input yields nil and the caller serves the whole
/// segment instead.
enum IFrameFragment {
    struct Trun {
        var offset: Int          // box start in the fragment
        var size: Int
        var flags: UInt32
        var sampleCount: Int
        var entrySize: Int
        var headerSize: Int      // bytes before the first entry (incl. data_offset / first_sample_flags)
        var dataOffsetField: Int? // offset of the data_offset field, when present
        var firstSampleSize: Int
    }

    static func firstSample(of seg: Data) -> Data? {
        guard seg.count >= 16, boxType(seg, at: 0) == "moof" else { return nil }
        let moofSize = Int(be32(seg, 0))
        guard moofSize >= 16, moofSize + 8 <= seg.count, boxType(seg, at: moofSize) == "mdat" else { return nil }
        // One traf (the video muxer is single-track); find traf, then trun inside it.
        guard let traf = child(seg, in: 8..<moofSize, type: "traf"),
              let trunRange = child(seg, in: (traf.lowerBound + 8)..<traf.upperBound, type: "trun"),
              let trun = parseTrun(seg, range: trunRange) else { return nil }
        guard trun.sampleCount >= 1, trun.firstSampleSize > 0 else { return nil }
        let mdatPayloadStart = moofSize + 8
        guard mdatPayloadStart + trun.firstSampleSize <= seg.count else { return nil }

        let dropped = (trun.sampleCount - 1) * trun.entrySize
        let newTrunSize = trun.size - dropped
        let newMoofSize = moofSize - dropped
        var out = Data(capacity: newMoofSize + 8 + trun.firstSampleSize)
        // moof header with the new size, then everything up to the traf box.
        var moofHead = seg.subdata(in: 0..<traf.lowerBound)
        write32(&moofHead, at: 0, UInt32(newMoofSize))
        out.append(moofHead)
        // traf header with the new size, then its children up to the trun.
        var trafHead = seg.subdata(in: traf.lowerBound..<trun.offset)
        write32(&trafHead, at: 0, UInt32((traf.upperBound - traf.lowerBound) - dropped))
        out.append(trafHead)
        // trun: header + first entry, size and sample_count rewritten, data_offset recomputed.
        var trunBox = seg.subdata(in: trun.offset..<(trun.offset + trun.headerSize + trun.entrySize))
        write32(&trunBox, at: 0, UInt32(newTrunSize))
        write32(&trunBox, at: 12, 1)
        if let field = trun.dataOffsetField {
            write32(&trunBox, at: field - trun.offset, UInt32(newMoofSize + 8))
        }
        out.append(trunBox)
        // Anything after the trun inside the traf (movenc writes none; keep it if present), and
        // anything after the traf inside the moof.
        out.append(seg.subdata(in: (trun.offset + trun.size)..<traf.upperBound))
        out.append(seg.subdata(in: traf.upperBound..<moofSize))
        guard out.count == newMoofSize else { return nil }
        // mdat with the first sample only.
        var mdatHead = Data(count: 8)
        write32(&mdatHead, at: 0, UInt32(8 + trun.firstSampleSize))
        mdatHead.replaceSubrange(4..<8, with: Array("mdat".utf8))
        out.append(mdatHead)
        out.append(seg.subdata(in: mdatPayloadStart..<(mdatPayloadStart + trun.firstSampleSize)))
        return out
    }

    // MARK: - Box walking

    static func child(_ d: Data, in range: Range<Int>, type: String) -> Range<Int>? {
        var p = range.lowerBound
        while p + 8 <= range.upperBound {
            let size = Int(be32(d, p))
            guard size >= 8, p + size <= range.upperBound else { return nil }
            if boxType(d, at: p) == type { return p..<(p + size) }
            p += size
        }
        return nil
    }

    static func parseTrun(_ d: Data, range: Range<Int>) -> Trun? {
        let o = range.lowerBound
        guard range.count >= 16 else { return nil }
        let flags = be32(d, o + 8) & 0x00FF_FFFF
        let count = Int(be32(d, o + 12))
        var p = o + 16
        var dataOffsetField: Int? = nil
        if flags & 0x1 != 0 { dataOffsetField = p; p += 4 }
        if flags & 0x4 != 0 { p += 4 }
        var entry = 0
        if flags & 0x100 != 0 { entry += 4 }
        if flags & 0x200 != 0 { entry += 4 }
        if flags & 0x400 != 0 { entry += 4 }
        if flags & 0x800 != 0 { entry += 4 }
        let header = p - o
        guard entry > 0, count >= 1, header + count * entry <= range.count else { return nil }
        // The first sample's size: the size field inside entry 0 (after an optional duration).
        guard flags & 0x200 != 0 else { return nil }   // movenc always writes per-sample sizes
        let sizeOffset = p + (flags & 0x100 != 0 ? 4 : 0)
        let firstSize = Int(be32(d, sizeOffset))
        return Trun(offset: o, size: range.count, flags: flags, sampleCount: count, entrySize: entry,
                    headerSize: header, dataOffsetField: dataOffsetField, firstSampleSize: firstSize)
    }

    static func boxType(_ d: Data, at p: Int) -> String {
        guard p + 8 <= d.count else { return "" }
        return String(decoding: d.subdata(in: (p + 4)..<(p + 8)), as: UTF8.self)
    }

    static func be32(_ d: Data, _ p: Int) -> UInt32 {
        guard p + 4 <= d.count else { return 0 }
        return d.subdata(in: p..<(p + 4)).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func write32(_ d: inout Data, at p: Int, _ v: UInt32) {
        d[d.startIndex + p] = UInt8(v >> 24 & 0xFF)
        d[d.startIndex + p + 1] = UInt8(v >> 16 & 0xFF)
        d[d.startIndex + p + 2] = UInt8(v >> 8 & 0xFF)
        d[d.startIndex + p + 3] = UInt8(v & 0xFF)
    }
}
