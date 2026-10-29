import XCTest
@testable import NuvioTV

/// FEAT-35 (Detail revamp, Cinematic): pins the Cinematic scrim stops and enforces the plan's
/// "Steven's BUG-127 stops are the ceiling" rule point by point. The classic stops stay pinned by
/// `DetailScrimTests`, unchanged.
///
/// beta.19-rc1 verdict (D3, BUG-127): the Cinematic stops were lightened again after Steven's Oak
/// Street and Monstre photos (the art still read darkened). The tests below pin the new stops, keep
/// the Classic ceiling, and add three guards: the new scrim is lighter than build 284fd764's
/// everywhere (old stops kept here as literals), the text block keeps a floor of darkness so the
/// synopsis and meta stay legible, and the art region stays mostly clear.
final class DetailScrimCinematicTests: XCTestCase {

    func testCinematicStops() {
        XCTAssertEqual(DetailScrim.cinematicHorizontalLeading, 0.30, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicHorizontalMid, 0.06, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicHorizontalTrailing, 0.00, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicHorizontalTrailingOverPoster, 0.06, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicVerticalClearUntil, 0.40, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicVerticalBottom, 0.85, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicRadialOpacity, 0.50, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicRadialEndRadiusFraction, 0.62, accuracy: 1e-9)
    }

    /// The ceiling: above the bottom band the Cinematic composite is never darker than Classic's,
    /// with and without the poster layer. If this fails, lower `cinematicRadialOpacity` in 0.05 steps.
    /// Batch C (Steven rc2 reference photo): the ceiling holds for the art (y ≤ 0.4, above the bottom
    /// band); the band below is darker than Classic on purpose (`testBottomBandIsDark`).
    func testCinematicNeverDarkerThanClassic() {
        for overPoster in [false, true] {
            for i in 0...10 {
                for j in 0...4 {
                    let x = Double(i) / 10
                    let y = Double(j) / 10
                    let classic = DetailScrim.classicCompositeAlpha(x: x, y: y, overPoster: overPoster)
                    let cinematic = DetailScrim.cinematicCompositeAlpha(x: x, y: y, overPoster: overPoster)
                    XCTAssertLessThanOrEqual(cinematic, classic + 1e-9,
                                             "x=\(x) y=\(y) overPoster=\(overPoster)")
                }
            }
        }
    }

    /// Spot values of the composite math, so a change to the helpers is caught even when the
    /// ceiling still holds.
    func testCompositeSpotValues() {
        // Top-left: classic is the horizontal leading stop alone (the vertical is still clear).
        XCTAssertEqual(DetailScrim.classicCompositeAlpha(x: 0, y: 0, overPoster: false), 0.80, accuracy: 1e-9)
        // Bottom-left: 1 − (1 − 0.80)(1 − 0.70).
        XCTAssertEqual(DetailScrim.classicCompositeAlpha(x: 0, y: 1, overPoster: false), 0.94, accuracy: 1e-9)
        // Cinematic bottom-left adds the full radial: 1 − (1 − 0.30)(1 − 0.85)(1 − 0.50) = 0.9475.
        XCTAssertEqual(DetailScrim.cinematicCompositeAlpha(x: 0, y: 1, overPoster: false), 0.9475, accuracy: 1e-9)
        // Top-right of the cinematic scrim, no poster: the radial is out of reach and both gradients
        // are clear there. With the poster layer the over-poster trailing stop alone shows.
        XCTAssertEqual(DetailScrim.cinematicCompositeAlpha(x: 1, y: 0, overPoster: false), 0, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicCompositeAlpha(x: 1, y: 0, overPoster: true), 0.06, accuracy: 1e-9)
        // Top-left: the horizontal leading stop plus a sliver of the radial (distance 1080 of 1190.4):
        // 1 − 0.70 × (1 − 0.50 × (1 − 1080 / 1190.4)) = 0.3325.
        XCTAssertEqual(DetailScrim.cinematicCompositeAlpha(x: 0, y: 0, overPoster: false), 0.3325, accuracy: 1e-3)
    }

    /// The beta.18 / build 284fd764 Cinematic stops, as literals: the D3 change must be lighter than
    /// these at every point, with and without the poster layer. (A 21 × 21 grid, finer than the
    /// ceiling test above.)
    func testLighterThanBuild284Everywhere() {
        let old = (leading: 0.55, mid: 0.15, trailing: 0.00, trailingOverPoster: 0.10,
                   clearUntil: 0.60, bottom: 0.60, radial: 0.55, radius: 0.70)
        func oldComposite(x: Double, y: Double, overPoster: Bool) -> Double {
            let t = min(max(x, 0), 1)
            let end = overPoster ? old.trailingOverPoster : old.trailing
            let horizontal = t <= 0.5
                ? old.leading + (old.mid - old.leading) * (t / 0.5)
                : old.mid + (end - old.mid) * ((t - 0.5) / 0.5)
            let ty = min(max(y, 0), 1)
            let vertical = ty > old.clearUntil ? old.bottom * (ty - old.clearUntil) / (1 - old.clearUntil) : 0
            let dx = x * DetailScrim.compositeAspectWidth
            let dy = (1 - y) * DetailScrim.compositeAspectHeight
            let distance = (dx * dx + dy * dy).squareRoot()
            let radial = old.radial * max(0, 1 - distance / (old.radius * DetailScrim.compositeAspectWidth))
            return 1 - (1 - horizontal) * (1 - vertical) * (1 - radial)
        }
        // The old literals really are build 284's: its bottom-left composite was 0.919.
        XCTAssertEqual(oldComposite(x: 0, y: 1, overPoster: false), 0.919, accuracy: 1e-9)
        for overPoster in [false, true] {
            for i in 0...20 {
                for j in 0...8 {   // Batch C: the art (y ≤ 0.4); the bottom band is darker on purpose.
                    let x = Double(i) / 20
                    let y = Double(j) / 20
                    let now = DetailScrim.cinematicCompositeAlpha(x: x, y: y, overPoster: overPoster)
                    XCTAssertLessThanOrEqual(now, oldComposite(x: x, y: y, overPoster: overPoster) + 1e-9,
                                             "x=\(x) y=\(y) overPoster=\(overPoster)")
                }
            }
        }
    }

    /// Mean and minimum composite darkness over `region` on a 21 × 21 grid.
    private func stats(x: ClosedRange<Double>, y: ClosedRange<Double>, overPoster: Bool) -> (mean: Double, min: Double) {
        var sum = 0.0
        var lowest = 1.0
        for i in 0...20 {
            for j in 0...20 {
                let px = x.lowerBound + (x.upperBound - x.lowerBound) * Double(i) / 20
                let py = y.lowerBound + (y.upperBound - y.lowerBound) * Double(j) / 20
                let value = DetailScrim.cinematicCompositeAlpha(x: px, y: py, overPoster: overPoster)
                sum += value
                lowest = min(lowest, value)
            }
        }
        return (sum / 441, lowest)
    }

    /// The synopsis/meta block (x 0.03–0.30, y 0.55–0.75) keeps enough darkness under it to stay
    /// legible: mean 0.638 and minimum 0.457 with the Batch C band (0.485 / 0.311 with D3). If a future
    /// lightening trips this, the text needs its own panel first.
    func testTextBlockFloor() {
        let block = stats(x: 0.03...0.30, y: 0.55...0.75, overPoster: false)
        XCTAssertGreaterThanOrEqual(block.mean, 0.45, "the text block's mean darkness fell below the legibility floor")
        XCTAssertGreaterThanOrEqual(block.min, 0.30, "a point under the text block fell below the legibility floor")
    }

    /// UX-18 (2026-10-22): the meta and ratings lines (x 0.03–0.30, y 0.44–0.54) sit above the
    /// synopsis block and had no floor of their own (mean 0.473, minimum 0.323 before the shelf).
    func testMetaLineFloor() {
        let band = stats(x: 0.03...0.30, y: 0.44...0.54, overPoster: false)
        XCTAssertGreaterThanOrEqual(band.mean, 0.55, "the meta band's mean darkness fell below the legibility floor")
        XCTAssertGreaterThanOrEqual(band.min, 0.40, "a point under the meta line fell below the legibility floor")
    }

    /// UX-18: the shelf is confined to the text column; it is zero right of the midline and outside
    /// its band, and the synopsis block's floor (`testTextBlockFloor`) is unchanged by it.
    func testShelfStaysUnderTheTextColumn() {
        XCTAssertEqual(DetailScrim.cinematicShelfAlpha(x: 0.5, y: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicShelfAlpha(x: 0.0, y: 0.30), 0, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicShelfAlpha(x: 0.0, y: 0.70), 0, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicShelfAlpha(x: 0.0, y: 0.50), DetailScrim.cinematicShelfOpacity, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicShelfAlpha(x: 0.25, y: 0.50), DetailScrim.cinematicShelfOpacity / 2, accuracy: 1e-9)
        XCTAssertEqual(DetailScrim.cinematicShelfAlpha(x: 0.0, y: 0.40), DetailScrim.cinematicShelfOpacity / 2, accuracy: 1e-9)
    }

    /// UX-18 (review r1 P2-6): the baked shelf bitmap is the oracle sampled: spot pixels match
    /// `cinematicShelfAlpha` within the 8-bit quantum, and the right half and the bands outside are clear.
    func testShelfBitmapSamplesTheOracle() throws {
        let image = DetailScrimShelf.image
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cg.width, DetailScrimShelf.width)
        XCTAssertEqual(cg.height, DetailScrimShelf.height)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                              bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        func alpha(col: Int, row: Int) -> Double { Double(pixels[(row * cg.width + col) * 4 + 3]) / 255 }
        for (x, y) in [(0.0, 0.50), (0.25, 0.50), (0.10, 0.40), (0.10, 0.58), (0.60, 0.50), (0.10, 0.30), (0.10, 0.70)] {
            let col = min(cg.width - 1, Int(x * Double(cg.width))), row = min(cg.height - 1, Int(y * Double(cg.height)))
            let expected = DetailScrim.cinematicShelfAlpha(x: (Double(col) + 0.5) / Double(cg.width),
                                                           y: (Double(row) + 0.5) / Double(cg.height))
            XCTAssertEqual(alpha(col: col, row: row), expected, accuracy: 1.5 / 255, "x=\(x) y=\(y)")
        }
    }

    /// The art region above the bottom band (x 0.5–1, y 0–0.4, no poster layer) stays mostly clear:
    /// mean 0.031.
    func testArtRegionMostlyClear() {
        // Batch C: the art above the bottom band (y 0–0.4) keeps rc1's D3 look.
        let art = stats(x: 0.5...1.0, y: 0.0...0.4, overPoster: false)
        XCTAssertLessThanOrEqual(art.mean, 0.04, "the art region is darker than the D3 target")
    }

    /// Batch C (Steven, rc2 reference photo): the bottom quarter, full width, is dark enough for the
    /// meta line, synopsis, buttons and the first row to read on bright art.
    func testBottomBandIsDark() {
        let band = stats(x: 0.0...1.0, y: 0.75...1.0, overPoster: false)
        XCTAssertGreaterThanOrEqual(band.mean, 0.6, "the bottom band is lighter than the reference look")
    }
}
