import XCTest
import CoreGraphics
@testable import NuvioTV

final class HDRThumbnailToneMapTests: XCTestCase {
    typealias M = HDRThumbnailToneMap

    private let pq2020 = M.ColorInfo(transfer: .pq, primaries: .bt2020)
    private let hlg2020 = M.ColorInfo(transfer: .hlg, primaries: .bt2020)

    private func code(_ signal: Double) -> UInt16 { UInt16((min(max(signal, 0), 1) * 65535).rounded()) }

    /// One pixel through the tone map; returns (r, g, b).
    private func pixel(_ r: UInt16, _ g: UInt16, _ b: UInt16, _ c: M.ColorInfo, mastering: Double? = nil) -> (Int, Int, Int) {
        let out = M.toneMapBGRX(rgb48: [r, g, b], width: 1, height: 1, color: c, masteringMaxNits: mastering)
        XCTAssertEqual(out.count, 4)
        XCTAssertEqual(out[3], 0xFF)
        return (Int(out[2]), Int(out[1]), Int(out[0]))
    }

    /// The formula's 8-bit value for a grey of `nits` (computed here, not by the type: C5).
    private func expectedGrey(nits: Double, peakNits: Double = 1000) -> Int {
        let l = nits / 203 * M.exposure
        let lw = peakNits / 203
        let shoulder = l * (1 + l / (lw * lw)) / (1 + l)
        let linear = min(max(shoulder, 0), 1)
        let srgb = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return Int((srgb * 255).rounded())
    }

    // C5: reference white lands where the curve puts it (≈ 191), not 255.
    func testPQReferenceWhiteGreyLandsAtFormulaValue() {
        let v = code(M.pqSignal(nits: 203))
        let expected = expectedGrey(nits: 203)
        XCTAssertEqual(expected, 191, accuracy: 2, "sanity: 0.52 linear through sRGB")
        let (r, g, b) = pixel(v, v, v, pq2020)
        for c in [r, g, b] { XCTAssertEqual(c, expected, accuracy: 3) }
        XCTAssertEqual(r, g, accuracy: 1); XCTAssertEqual(g, b, accuracy: 1)
    }

    func testPQZeroIsBlackAndTenThousandNitsClipsWithoutWrap() {
        XCTAssertTrue(pixel(0, 0, 0, pq2020) == (0, 0, 0))
        let (r, g, b) = pixel(65535, 65535, 65535, pq2020)
        XCTAssertEqual([r, g, b], [255, 255, 255])
        // Monotonic up the ramp: no wrap anywhere.
        var last = -1
        for k in stride(from: 0, through: 65535, by: 1024) {
            let v = UInt16(k)
            let (r, _, _) = pixel(v, v, v, pq2020)
            XCTAssertGreaterThanOrEqual(r, last)
            last = r
        }
    }

    func testPeakNitsMapsToWhite() {
        let v = code(M.pqSignal(nits: 1000))
        let (r, _, _) = pixel(v, v, v, pq2020)
        XCTAssertEqual(r, 255, accuracy: 1, "shoulder(Lw) == 1")
        XCTAssertEqual(M.shoulder(1000 / 203, peak: 1000 / 203), 1, accuracy: 1e-12)
    }

    func testHLGReferenceSignalLandsNearReferenceWhite() {
        XCTAssertEqual(M.hlgSceneLinear(signal: 0.75), 0.265, accuracy: 0.001)
        let v = code(0.75)
        let (r, g, b) = pixel(v, v, v, hlg2020)
        let expected = expectedGrey(nits: 203)   // BT.2408: HLG 75 % ≈ 203 nits at a 1000-nit display
        for c in [r, g, b] { XCTAssertEqual(c, expected, accuracy: 3) }
        XCTAssertTrue(pixel(0, 0, 0, hlg2020) == (0, 0, 0))
        XCTAssertEqual(pixel(65535, 65535, 65535, hlg2020).0, 255)
    }

    func testSDRBT709PassesThrough() {
        let sdr = M.ColorInfo(transfer: .sdr, primaries: .bt709)
        XCTAssertTrue(pixel(0x8080, 0x4040, 0xFFFF, sdr) == (128, 64, 255))
        XCTAssertTrue(pixel(0, 257, 65535, sdr) == (0, 1, 255))
        // BT.2020 SDR grey stays grey at the same level.
        let sdr2020 = M.ColorInfo(transfer: .sdr, primaries: .bt2020)
        let (r, g, b) = pixel(0x8080, 0x8080, 0x8080, sdr2020)
        for c in [r, g, b] { XCTAssertEqual(c, 128, accuracy: 1) }
    }

    func testBT709HDRSkipsTheMatrix() {
        // A pure 709 red stays pure: no 2020 → 709 cross-talk.
        let pq709 = M.ColorInfo(transfer: .pq, primaries: .bt709)
        let v = code(M.pqSignal(nits: 400))
        let (r, g, b) = pixel(v, 0, 0, pq709)
        XCTAssertGreaterThan(r, 150)
        XCTAssertEqual(g, 0); XCTAssertEqual(b, 0)
    }

    func testSaturatedRedStaysRedDominantAndGreenClips() {
        let v = code(M.pqSignal(nits: 1000))
        let (r, g, b) = pixel(v, 0, 0, pq2020)
        XCTAssertGreaterThan(r, 200)
        XCTAssertGreaterThan(r, g * 4); XCTAssertGreaterThan(r, b * 4)
        // BT.2020 green is outside 709: red and blue go negative and clamp to 0, green clips.
        let (gr, gg, gb) = pixel(0, v, 0, pq2020)
        XCTAssertEqual(gr, 0); XCTAssertEqual(gb, 0)
        XCTAssertGreaterThan(gg, 200)
        XCTAssertLessThanOrEqual(gg, 255)
    }

    func testMasteringPeakClampAndHLGIgnoresIt() {
        XCTAssertEqual(M.peakWhite(transfer: .pq, masteringMaxNits: nil), 1000 / 203, accuracy: 1e-12)
        XCTAssertEqual(M.peakWhite(transfer: .pq, masteringMaxNits: 100), 400 / 203, accuracy: 1e-12)
        XCTAssertEqual(M.peakWhite(transfer: .pq, masteringMaxNits: 10000), 4000 / 203, accuracy: 1e-12)
        XCTAssertEqual(M.peakWhite(transfer: .hlg, masteringMaxNits: 4000), 1000 / 203, accuracy: 1e-12)
        let v = code(M.pqSignal(nits: 203))
        let (r, _, _) = pixel(v, v, v, pq2020, mastering: 4000)
        XCTAssertEqual(r, expectedGrey(nits: 203, peakNits: 4000), accuracy: 3)
    }

    func testFromDecodedFrameMapsFFmpegEnums() {
        XCTAssertEqual(M.avcolTrcSMPTE2084, 16)
        XCTAssertEqual(M.avcolTrcARIBSTDB67, 18)
        XCTAssertEqual(M.avcolPriBT2020, 9)
        XCTAssertEqual(M.fromDecodedFrame(trc: 16, primaries: 9), pq2020)
        XCTAssertEqual(M.fromDecodedFrame(trc: 18, primaries: 9), hlg2020)
        XCTAssertEqual(M.fromDecodedFrame(trc: 1, primaries: 1), .init(transfer: .sdr, primaries: .bt709))
        // The frame says unspecified: fall back to codecpar (C4).
        XCTAssertEqual(M.fromDecodedFrame(trc: 2, primaries: 2, codecparTrc: 16, codecparPrimaries: 9), pq2020)
        // The frame wins over codecpar when it says something.
        XCTAssertEqual(M.fromDecodedFrame(trc: 16, primaries: 9, codecparTrc: 1, codecparPrimaries: 1), pq2020)
        // HDR with unspecified primaries is BT.2020; SDR with nothing is BT.709.
        XCTAssertEqual(M.fromDecodedFrame(trc: 16, primaries: 2), pq2020)
        XCTAssertEqual(M.fromDecodedFrame(trc: 2, primaries: 2), .init(transfer: .sdr, primaries: .bt709))
        XCTAssertEqual(M.fromDecodedFrame(trc: 14, primaries: 9), .init(transfer: .sdr, primaries: .bt2020))
        XCTAssertFalse(M.fromDecodedFrame(trc: 1, primaries: 1).isHDR)
        XCTAssertTrue(pq2020.isHDR)
    }

    func testApplyMakesStoreFormatImageAndHonoursRowPadding() {
        let w = 320, h = 180, stride = w * 6 + 64
        var buf = [UInt8](repeating: 0, count: stride * h)
        let v = code(M.pqSignal(nits: 203))
        for y in 0..<h {
            for x in 0..<w * 3 {
                let o = y * stride + x * 2
                buf[o] = UInt8(v & 0xFF); buf[o + 1] = UInt8(v >> 8)
            }
        }
        let start = CFAbsoluteTimeGetCurrent()
        let image = buf.withUnsafeBytes {
            M.apply(rgb48: $0.baseAddress!, width: w, height: h, bytesPerRow: stride, color: pq2020)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[ToneMapTest] 320x180 tm=%.1fms", ms))
        XCTAssertEqual(image?.width, w)
        XCTAssertEqual(image?.height, h)
        XCTAssertEqual(image?.bitsPerPixel, 32)
        XCTAssertEqual(image?.alphaInfo, .noneSkipFirst)
        let bytes = buf.withUnsafeBytes {
            M.toneMapBGRX(rgb48: $0.baseAddress!, width: w, height: h, bytesPerRow: stride, color: pq2020)
        }
        let last = (w * h - 1) * 4
        XCTAssertEqual(Int(bytes[last]), expectedGrey(nits: 203), accuracy: 3, "the padded last row is read right")
        XCTAssertTrue(M.toneMapBGRX(rgb48: [1, 2], width: 1, height: 1, color: pq2020).isEmpty)
    }
}
