import CoreGraphics
import Foundation

/// Tone-maps a decoded HDR keyframe, already scaled to thumbnail size as 16-bit RGB (`RGB48LE`,
/// still the PQ or HLG signal, BT.2020 primaries), to an 8-bit sRGB thumbnail in the store's pixel
/// format (`bgr0`: `noneSkipFirst | byteOrder32Little`, like `PreviewFrameScaler`). Pure, no
/// FFmpeg, runs on any thread (P3 decision 1, option d).
///
/// Per pixel:
/// 1. Signal → linear through a 4096-entry table indexed by the top 12 bits (critique C12):
///    PQ = SMPTE ST 2084 EOTF in nits; HLG = the BT.2100 inverse OETF (scene light), then the
///    OOTF at a 1000-nit display (system gamma 1.2, on the BT.2020 luminance). Linear is in units
///    of reference white, `L = nits / 203` (BT.2408).
/// 2. BT.2020 → BT.709 linear matrix; negatives (out of the 709 gamut) clamp to 0.
/// 3. `exposure`, then the extended Reinhard shoulder `L' = L (1 + L / Lw²) / (1 + L)` on
///    max(R, G, B), applied as one scale to all three channels so the hue holds. `Lw` is the
///    peak in reference-white units: 1000 / 203 by default, the mastering display's max when the
///    frame carries one (clamped 400…4000 nits); always 1000 / 203 for HLG.
/// 4. Clamp 0…1, sRGB OETF through a 4096-entry table, 8 bits.
///
/// Critique C5, the choice made here: the curve stays as specified (it maps `Lw` to exactly 1.0,
/// so a highlight at the mastering peak reaches white and nothing above it wraps). Reference white
/// therefore lands at `L' ≈ 0.52` linear, about 191 of 255 after the sRGB curve, not 255; the
/// spec's "203 nits → 255" test contradicted its own formula and is replaced by a test that
/// derives the value from these constants. `exposure` (1.0) is the lever if the device pass finds
/// thumbnails dim.
///
/// SDR input (`transfer == .sdr`) is accepted so the thumbnailer can route every frame through
/// one function: BT.709 primaries pass through unchanged (16 → 8 bits, rounded); BT.2020 SDR is
/// linearised with the BT.1886 gamma 2.4, converted to BT.709, clamped and re-encoded with the same
/// gamma, so a 709 grey and a 2020 grey come out alike.
nonisolated enum HDRThumbnailToneMap {
    enum Transfer: String, Sendable { case pq, hlg, sdr }
    enum Primaries: String, Sendable { case bt2020, bt709 }

    struct ColorInfo: Equatable, Sendable {
        var transfer: Transfer
        var primaries: Primaries
        var isHDR: Bool { transfer != .sdr }
    }

    // MARK: FFmpeg enum values (libavutil/pixfmt.h), so the thumbnailer passes raw ints.

    /// `AVCOL_TRC_RESERVED0` and `AVCOL_TRC_UNSPECIFIED`: "the frame does not say".
    static let avcolTrcReserved0: Int32 = 0
    static let avcolTrcUnspecified: Int32 = 2
    /// `AVCOL_TRC_SMPTE2084` (PQ, HDR10 and the DV 8.1 / 7 base layer).
    static let avcolTrcSMPTE2084: Int32 = 16
    /// `AVCOL_TRC_ARIB_STD_B67` (HLG, and DV 8.4).
    static let avcolTrcARIBSTDB67: Int32 = 18
    static let avcolPriReserved0: Int32 = 0
    static let avcolPriBT709: Int32 = 1
    static let avcolPriUnspecified: Int32 = 2
    /// `AVCOL_PRI_BT2020`.
    static let avcolPriBT2020: Int32 = 9

    /// The colour info for a decoded frame (critique C4): the `AVFrame`'s `color_trc` and
    /// `color_primaries`, falling back to the stream's `codecpar` values only when the frame says
    /// unspecified. PQ and HLG with unspecified primaries are BT.2020 (no other HDR exists);
    /// anything else unspecified is BT.709. Every transfer other than PQ and HLG is SDR.
    static func fromDecodedFrame(trc: Int32, primaries: Int32,
                                 codecparTrc: Int32 = avcolTrcUnspecified,
                                 codecparPrimaries: Int32 = avcolPriUnspecified) -> ColorInfo {
        func unspecifiedTrc(_ v: Int32) -> Bool { v == avcolTrcUnspecified || v == avcolTrcReserved0 }
        func unspecifiedPri(_ v: Int32) -> Bool { v == avcolPriUnspecified || v == avcolPriReserved0 }
        let t = unspecifiedTrc(trc) ? codecparTrc : trc
        let p = unspecifiedPri(primaries) ? codecparPrimaries : primaries
        let transfer: Transfer = t == avcolTrcSMPTE2084 ? .pq : (t == avcolTrcARIBSTDB67 ? .hlg : .sdr)
        let prim: Primaries
        if p == avcolPriBT2020 { prim = .bt2020 }
        else if unspecifiedPri(p) { prim = transfer == .sdr ? .bt709 : .bt2020 }
        else { prim = .bt709 }
        return ColorInfo(transfer: transfer, primaries: prim)
    }

    // MARK: Constants

    static let referenceWhiteNits = 203.0
    static let defaultPeakNits = 1000.0
    static let hlgDisplayPeakNits = 1000.0
    static let hlgSystemGamma = 1.2
    /// Tune on the device pass (critique C5); 1.0 = reference white at the curve's own value.
    static let exposure = 1.0
    static let lutSize = 4096

    /// BT.2020 → BT.709, linear light (ITU-R BT.2087, rows R, G, B).
    static let bt2020ToBT709: [[Double]] = [
        [1.6605, -0.5876, -0.0728],
        [-0.1246, 1.1329, -0.0083],
        [-0.0182, -0.1006, 1.1187],
    ]
    /// BT.2020 luminance weights (HLG OOTF).
    static let bt2020Luma = (r: 0.2627, g: 0.6780, b: 0.0593)

    /// `Lw` in reference-white units. PQ: the mastering max when known (clamped 400…4000 nits),
    /// else 1000; HLG: the OOTF's 1000-nit display.
    static func peakWhite(transfer: Transfer, masteringMaxNits: Double?) -> Double {
        switch transfer {
        case .hlg: return hlgDisplayPeakNits / referenceWhiteNits
        case .pq:
            let nits = masteringMaxNits.flatMap { $0.isFinite && $0 > 0 ? min(max($0, 400), 4000) : nil }
            return (nits ?? defaultPeakNits) / referenceWhiteNits
        case .sdr: return 1
        }
    }

    /// The extended Reinhard shoulder: `L (1 + L / Lw²) / (1 + L)`; `shoulder(Lw, Lw) == 1`.
    static func shoulder(_ l: Double, peak lw: Double) -> Double {
        guard l > 0 else { return 0 }
        return l * (1 + l / (lw * lw)) / (1 + l)
    }

    // MARK: Transfer functions

    private static let pqM1 = 2610.0 / 16384, pqM2 = 2523.0 / 4096 * 128
    private static let pqC1 = 3424.0 / 4096, pqC2 = 2413.0 / 4096 * 32, pqC3 = 2392.0 / 4096 * 32

    /// ST 2084 EOTF: signal 0…1 → nits 0…10000.
    static func pqNits(signal e: Double) -> Double {
        let ep = pow(min(max(e, 0), 1), 1 / pqM2)
        return 10000 * pow(max(ep - pqC1, 0) / (pqC2 - pqC3 * ep), 1 / pqM1)
    }

    /// ST 2084 inverse EOTF: nits → signal 0…1 (tests build PQ code values with it).
    static func pqSignal(nits: Double) -> Double {
        let y = pow(min(max(nits, 0), 10000) / 10000, pqM1)
        return pow((pqC1 + pqC2 * y) / (1 + pqC3 * y), pqM2)
    }

    private static let hlgA = 0.17883277, hlgB = 0.28466892, hlgC = 0.55991073

    /// BT.2100 HLG inverse OETF: signal 0…1 → scene linear 0…1.
    static func hlgSceneLinear(signal e: Double) -> Double {
        let e = min(max(e, 0), 1)
        return e <= 0.5 ? e * e / 3 : (exp((e - hlgC) / hlgA) + hlgB) / 12
    }

    static func srgbEncode(_ l: Double) -> Double {
        let l = min(max(l, 0), 1)
        return l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    // MARK: Tables (C12)

    /// PQ signal → linear in reference-white units.
    private static let pqTable: [Float] = (0..<lutSize).map {
        Float(pqNits(signal: Double($0) / Double(lutSize - 1)) / referenceWhiteNits)
    }
    /// HLG signal → scene linear 0…1.
    private static let hlgTable: [Float] = (0..<lutSize).map {
        Float(hlgSceneLinear(signal: Double($0) / Double(lutSize - 1)))
    }
    /// BT.1886 (gamma 2.4) signal → linear 0…1, for BT.2020 SDR.
    private static let gammaTable: [Float] = (0..<lutSize).map {
        Float(pow(Double($0) / Double(lutSize - 1), 2.4))
    }
    /// Linear 0…1 → 8-bit sRGB.
    private static let srgbTable: [UInt8] = (0..<lutSize).map {
        UInt8((srgbEncode(Double($0) / Double(lutSize - 1)) * 255).rounded())
    }
    /// Linear 0…1 → 8-bit gamma 1 / 2.4 (BT.2020 SDR re-encode).
    private static let gammaEncodeTable: [UInt8] = (0..<lutSize).map {
        UInt8((pow(Double($0) / Double(lutSize - 1), 1 / 2.4) * 255).rounded())
    }

    @inline(__always) private static func lutIndex(_ v: UInt16) -> Int { min((Int(v) + 8) >> 4, lutSize - 1) }
    @inline(__always) private static func linIndex(_ x: Float) -> Int {
        Int(min(max(x, 0), 1) * Float(lutSize - 1) + 0.5)
    }

    // MARK: Apply

    /// Tone-maps `width × height` RGB48LE pixels (`bytesPerRow` may pad, as `sws_scale` does) to
    /// tightly packed `bgr0` bytes (B, G, R, 0xFF per pixel).
    static func toneMapBGRX(rgb48: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
                            color: ColorInfo, masteringMaxNits: Double? = nil) -> [UInt8] {
        guard width > 0, height > 0, bytesPerRow >= width * 6 else { return [] }
        var out = [UInt8](repeating: 0xFF, count: width * height * 4)
        let m = bt2020ToBT709.map { $0.map(Float.init) }
        let (m00, m01, m02) = (m[0][0], m[0][1], m[0][2])
        let (m10, m11, m12) = (m[1][0], m[1][1], m[1][2])
        let (m20, m21, m22) = (m[2][0], m[2][1], m[2][2])
        let convert = color.primaries == .bt2020
        let lw = Float(peakWhite(transfer: color.transfer, masteringMaxNits: masteringMaxNits))
        let invLw2 = 1 / (lw * lw)
        let expo = Float(exposure)
        let hlgPeak = Float(hlgDisplayPeakNits / referenceWhiteNits)
        let hlgExp = Float(hlgSystemGamma - 1)
        let (kr, kg, kb) = (Float(bt2020Luma.r), Float(bt2020Luma.g), Float(bt2020Luma.b))

        let decodeTable: [Float]
        let encodeTable: [UInt8]
        switch color.transfer {
        case .pq: decodeTable = pqTable; encodeTable = srgbTable
        case .hlg: decodeTable = hlgTable; encodeTable = srgbTable
        case .sdr: decodeTable = gammaTable; encodeTable = gammaEncodeTable
        }
        let sdrPassthrough = color.transfer == .sdr && !convert

        decodeTable.withUnsafeBufferPointer { dec in
            encodeTable.withUnsafeBufferPointer { enc in
                out.withUnsafeMutableBufferPointer { dst in
                    for y in 0..<height {
                        let row = rgb48.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt16.self)
                        var o = y * width * 4
                        for x in 0..<width {
                            let rv = UInt16(littleEndian: row[x * 3])
                            let gv = UInt16(littleEndian: row[x * 3 + 1])
                            let bv = UInt16(littleEndian: row[x * 3 + 2])
                            if sdrPassthrough {
                                dst[o] = UInt8((UInt32(bv) * 255 + 32767) / 65535)
                                dst[o + 1] = UInt8((UInt32(gv) * 255 + 32767) / 65535)
                                dst[o + 2] = UInt8((UInt32(rv) * 255 + 32767) / 65535)
                                o += 4
                                continue
                            }
                            var r = dec[lutIndex(rv)], g = dec[lutIndex(gv)], b = dec[lutIndex(bv)]
                            if color.transfer == .hlg {
                                // OOTF on the scene luminance (BT.2020 weights), 1000-nit display.
                                let ys = kr * r + kg * g + kb * b
                                let gain = ys > 0 ? hlgPeak * powf(ys, hlgExp) : 0
                                r *= gain; g *= gain; b *= gain
                            }
                            if convert {
                                let r2 = m00 * r + m01 * g + m02 * b
                                let g2 = m10 * r + m11 * g + m12 * b
                                let b2 = m20 * r + m21 * g + m22 * b
                                r = max(r2, 0); g = max(g2, 0); b = max(b2, 0)
                            }
                            if color.transfer != .sdr {
                                r *= expo; g *= expo; b *= expo
                                let peak = max(r, max(g, b))
                                if peak > 0 {
                                    let scale = (1 + peak * invLw2) / (1 + peak)   // shoulder(peak) / peak
                                    r *= scale; g *= scale; b *= scale
                                }
                            }
                            dst[o] = enc[linIndex(b)]
                            dst[o + 1] = enc[linIndex(g)]
                            dst[o + 2] = enc[linIndex(r)]
                            o += 4
                        }
                    }
                }
            }
        }
        return out
    }

    /// Tightly packed `[R, G, B, R, G, B, …]` 16-bit samples (tests).
    static func toneMapBGRX(rgb48 samples: [UInt16], width: Int, height: Int, color: ColorInfo,
                            masteringMaxNits: Double? = nil) -> [UInt8] {
        guard samples.count >= width * height * 3 else { return [] }
        let le = samples.map { $0.littleEndian }
        return le.withUnsafeBytes {
            toneMapBGRX(rgb48: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 6,
                        color: color, masteringMaxNits: masteringMaxNits)
        }
    }

    /// The thumbnail as a `CGImage` in the store's format (sRGB, `bgr0`).
    static func apply(rgb48: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
                      color: ColorInfo, masteringMaxNits: Double? = nil) -> CGImage? {
        let bytes = toneMapBGRX(rgb48: rgb48, width: width, height: height, bytesPerRow: bytesPerRow,
                                color: color, masteringMaxNits: masteringMaxNits)
        guard !bytes.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
