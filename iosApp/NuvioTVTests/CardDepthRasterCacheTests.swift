import XCTest
import SwiftUI
import UIKit
@testable import NuvioTV

/// W3-13 (UX-16 / BUG-153 remainder): the pure halves of the Card Depth raster fix.
/// - The white-rail × tint identity: the rail now strokes white at the stop alphas and takes the
///   poster colour by `.colorMultiply`, which must paint what `railColor(tint).opacity(stop)` painted
///   at every stop (`CardDepthStyle.multipliedRailStop` vs `tintedRailStop`, the latter checked
///   against SwiftUI's own colour resolution).
/// - `CardDepthRasterCache` (render variant 2): a key per width, alpha, radius, shape, size, scale
///   and coverage, so no two rails that differ on screen can share a bitmap (test60's three levels
///   stay three bitmaps), and bitmaps that match the live layers' geometry and stops.
@MainActor
final class CardDepthRasterCacheTests: XCTestCase {

    private typealias Cache = CardDepthRasterCache
    private typealias Key = CardDepthRasterCache.Key

    /// A Medium+ poster's inset artwork box and BUG-91's inner radius (12 − 4).
    private let poster = CGSize(width: 126, height: 193)
    private let inner8 = Cache.ShapeKind.roundedRect(cornerWidthX100: 800, cornerHeightX100: 800, continuous: true)

    private func railKey(size: CGSize? = nil, scale: CGFloat = 1, shape: Cache.ShapeKind? = nil,
                         strength: Int = 28, coverage: Double = 1) -> Key {
        let edge = Double(strength) / 100
        return .rail(size: size ?? poster, scale: scale, shape: shape ?? inner8,
                     lineWidth: CardDepthStyle.railWidth(edgeStrength: strength),
                     stops: CardDepthStyle.railStops(edge: edge, coverage: coverage),
                     coverage: coverage)
    }

    // MARK: - White rail × tint

    private let tints: [CardDepthRGBA?] = [
        nil,
        .white,
        CardDepthRGBA(red: 0.92, green: 0.47, blue: 0.28, alpha: 1),   // a railLifted orange
        CardDepthRGBA(red: 0.30, green: 0.62, blue: 1.00, alpha: 1),   // a railLifted blue
        CardDepthRGBA(red: 0, green: 0, blue: 0, alpha: 1),
        CardDepthRGBA(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.5),  // translucent, not produced today
    ]

    /// Every stop of every strength and coverage the rail can draw, Off through the 100 ceiling.
    private var everyStop: [Double] {
        var out: [Double] = [0, 1]
        for strength in [0, 1, 20, 28, 30, 42, 50, 56, 80, 100] {
            for coverage in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let stops = CardDepthStyle.railStops(edge: Double(strength) / 100, coverage: coverage)
                out += [stops.top, stops.mid, stops.bottom, CardDepthStyle.railHaloAlpha(edge: Double(strength) / 100)]
            }
        }
        return out
    }

    func testWhiteRailTimesTintEqualsTheTintedStopAtEveryStop() {
        for tint in tints {
            for stop in everyStop {
                XCTAssertEqual(CardDepthStyle.multipliedRailStop(tint: tint, stop: stop),
                               CardDepthStyle.tintedRailStop(tint: tint, stop: stop),
                               "tint \(String(describing: tint)) stop \(stop)")
            }
        }
    }

    func testANilTintMultipliesByWhiteAndLeavesTheWhiteRail() {
        for stop in everyStop {
            XCTAssertEqual(CardDepthStyle.multipliedRailStop(tint: nil, stop: stop),
                           CardDepthStyle.whiteRailStop(alpha: stop))
            XCTAssertEqual(CardDepthStyle.colorMultiplied(CardDepthStyle.whiteRailStop(alpha: stop), by: .white),
                           CardDepthStyle.whiteRailStop(alpha: stop))
        }
    }

    func testMultiplyIsComponentwiseIncludingAlpha() {
        let product = CardDepthStyle.colorMultiplied(CardDepthRGBA(red: 0.5, green: 0.25, blue: 1, alpha: 0.8),
                                                     by: CardDepthRGBA(red: 0.5, green: 1, blue: 0.1, alpha: 0.5))
        XCTAssertEqual(product.red, 0.25, accuracy: 1e-12)
        XCTAssertEqual(product.green, 0.25, accuracy: 1e-12)
        XCTAssertEqual(product.blue, 0.1, accuracy: 1e-12)
        XCTAssertEqual(product.alpha, 0.4, accuracy: 1e-12)
    }

    /// Ties the pure functions to SwiftUI: `railColor(tint).opacity(stop)` (what the rail painted)
    /// resolves to `tintedRailStop`, `.white.opacity(stop)` (what it strokes now) to `whiteRailStop`,
    /// and white × the resolved tint lands on the old colour.
    func testThePureStopsAreSwiftUIsOwnColours() {
        let environment = EnvironmentValues()
        let colours: [Color?] = [nil, .white, .orange, .blue,
                                 Color(.sRGB, red: 0.92, green: 0.47, blue: 0.28, opacity: 1)]
        for colour in colours {
            let tint = colour.map { CardDepthRGBA($0.resolve(in: environment)) }
            for stop in [0, 0.09, 0.28, 0.35, 0.6, 0.8, 0.95, 1] {
                let old = CardDepthRGBA(CardDepthStyle.railColor(tint: colour).opacity(stop).resolve(in: environment))
                let white = CardDepthRGBA(Color.white.opacity(stop).resolve(in: environment))
                assertClose(old, CardDepthStyle.tintedRailStop(tint: tint, stop: stop), "old, \(String(describing: colour)) @ \(stop)")
                assertClose(white, CardDepthStyle.whiteRailStop(alpha: stop), "white @ \(stop)")
                assertClose(CardDepthStyle.colorMultiplied(white, by: tint ?? .white), old, "white × tint, \(String(describing: colour)) @ \(stop)")
            }
        }
    }

    private func assertClose(_ a: CardDepthRGBA, _ b: CardDepthRGBA, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let accuracy = 1e-6
        XCTAssertEqual(a.red, b.red, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.green, b.green, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.blue, b.blue, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.alpha, b.alpha, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: - Cache keys

    func testRailKeyIsDistinctPerWidth() {
        // Same stops, three widths.
        let stops = CardDepthStyle.railStops(edge: 0.28, coverage: 1)
        let keys = [1, 2, 3].map { width in
            Key.rail(size: poster, scale: 1, shape: inner8, lineWidth: CGFloat(width), stops: stops, coverage: 1)
        }
        XCTAssertEqual(Set(keys).count, 3)
    }

    func testRailKeyIsDistinctPerAlpha() {
        // Same width, stops one hundredth apart in each position.
        let base = Key.rail(size: poster, scale: 1, shape: inner8, lineWidth: 1, stops: (0.35, 0.28, 0.28), coverage: 1)
        let top = Key.rail(size: poster, scale: 1, shape: inner8, lineWidth: 1, stops: (0.36, 0.28, 0.28), coverage: 1)
        let mid = Key.rail(size: poster, scale: 1, shape: inner8, lineWidth: 1, stops: (0.35, 0.29, 0.28), coverage: 1)
        let bottom = Key.rail(size: poster, scale: 1, shape: inner8, lineWidth: 1, stops: (0.35, 0.28, 0.29), coverage: 1)
        XCTAssertEqual(Set([base, top, mid, bottom]).count, 4)
    }

    func testRailKeyIsDistinctPerRadius() {
        let radii: [Cache.ShapeKind] = [0, 4, 8, 8.5, 12].map {
            .roundedRect(cornerWidthX100: Key.x100($0), cornerHeightX100: Key.x100($0), continuous: true)
        }
        XCTAssertEqual(Set(radii.map { railKey(shape: $0) }).count, radii.count)
    }

    func testRailKeyIsDistinctPerShapeKind() {
        let circular = Cache.ShapeKind.roundedRect(cornerWidthX100: 800, cornerHeightX100: 800, continuous: false)
        let keys = [railKey(shape: inner8), railKey(shape: circular), railKey(shape: .circle)]
        XCTAssertEqual(Set(keys).count, 3)
    }

    func testRailKeyIsDistinctPerSizeScaleAndCoverage() {
        let keys = [
            railKey(),
            railKey(size: CGSize(width: 134, height: 201)),
            railKey(size: CGSize(width: 126, height: 194)),
            railKey(scale: 2),
            railKey(coverage: 0),
            railKey(coverage: 0.5),
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// test60's triptych must stay three different bitmaps.
    func testTheThreeLevelsAreThreeKeys() {
        let keys = [28, 42, 56].map { railKey(strength: $0) }
        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(keys.map(\.railWidthX100), [100, 200, 300])
        XCTAssertEqual(keys.map(\.topX100), [35, 60, 80])
    }

    func testEqualInputsShareAKeyAndSubPixelNoiseRoundsAway() {
        XCTAssertEqual(railKey(), railKey())
        XCTAssertEqual(railKey(size: CGSize(width: 126.2, height: 192.9)), railKey())
        // At 2x the same 0.4 pt is most of a pixel: a different bitmap.
        XCTAssertNotEqual(railKey(size: CGSize(width: 126.4, height: 193), scale: 2), railKey(scale: 2))
        XCTAssertEqual(railKey().pixelWidth, 126)
        XCTAssertEqual(railKey(scale: 2).pixelHeight, 386)
    }

    func testSheenKeyIgnoresTheRailAndTheRailKeyIgnoresTheSheen() {
        let sheen = Key.sheen(size: poster, scale: 1, shape: inner8, sheen: 0.10)
        XCTAssertEqual(sheen.railWidthX100, 0)
        XCTAssertEqual(sheen.topX100, 0)
        XCTAssertEqual(sheen.sheenX100, 10)
        XCTAssertEqual(railKey().sheenX100, 0)
        XCTAssertNotEqual(sheen, Key.sheen(size: poster, scale: 1, shape: inner8, sheen: 0.20))
        XCTAssertNotEqual(sheen, Key.sheen(size: poster, scale: 1, shape: .circle, sheen: 0.10))
        XCTAssertNotEqual(sheen.layer, railKey().layer)
    }

    func testShapeKindsOfTheCallSiteShapes() {
        XCTAssertEqual(Cache.ShapeKind(RoundedRectangle(cornerRadius: 8)), inner8)
        XCTAssertEqual(Cache.ShapeKind(RoundedRectangle(cornerRadius: 8, style: .circular)),
                       .roundedRect(cornerWidthX100: 800, cornerHeightX100: 800, continuous: false))
        XCTAssertEqual(Cache.ShapeKind(RoundedRectangle(cornerSize: CGSize(width: 6, height: 9))),
                       .roundedRect(cornerWidthX100: 600, cornerHeightX100: 900, continuous: true))
        XCTAssertEqual(Cache.ShapeKind(Circle()), .circle)
        XCTAssertNil(Cache.ShapeKind(Capsule()), "an unkeyed shape must fall back to variant 1")
        XCTAssertNil(Cache.ShapeKind(Rectangle()))
    }

    // MARK: - Geometry: the live layers' own paths

    func testTheRailPathIsStrokeBordersInsetPath() {
        let rect = CGRect(origin: .zero, size: poster)
        for width: CGFloat in [1, 2, 3] {
            XCTAssertEqual(Cache.shapePath(inner8, in: rect, inset: width / 2),
                           RoundedRectangle(cornerRadius: 8).inset(by: width / 2).path(in: rect))
            XCTAssertEqual(Cache.shapePath(.circle, in: rect, inset: width / 2),
                           Circle().inset(by: width / 2).path(in: rect))
        }
        XCTAssertEqual(Cache.shapePath(inner8, in: rect, inset: 0), RoundedRectangle(cornerRadius: 8).path(in: rect))
    }

    // MARK: - Rendering

    func testBitmapSizeAndScaleComeFromTheKey() throws {
        let image = try XCTUnwrap(Cache.render(railKey(scale: 2)))
        XCTAssertEqual(image.scale, 2)
        XCTAssertEqual(image.size.width, 126, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 193, accuracy: 0.001)
        XCTAssertEqual(image.cgImage?.width, 252)
        XCTAssertEqual(image.cgImage?.height, 386)
    }

    func testAnEmptySizeRendersNothing() {
        XCTAssertNil(Cache.render(railKey(size: .zero)))
        XCTAssertNil(CardDepthRasterCache().image(for: railKey(size: CGSize(width: 0, height: 193))))
    }

    func testTheFullRailIsWhiteAtTheKeyedStops() throws {
        // Bold, Full: 3 pt, top 0.80, mid/bottom 0.56.
        let key = railKey(strength: 56, coverage: 1)
        let pixels = try Pixels(XCTUnwrap(Cache.render(key)))
        let midX = pixels.width / 2
        let top = pixels.at(midX, 1)
        XCTAssertEqual(top.a, 0.80, accuracy: 0.02, "top edge alpha")
        XCTAssertEqual(top.r, top.a, accuracy: 0.01, "white (premultiplied r == a)")
        XCTAssertEqual(pixels.at(midX, pixels.height - 2).a, 0.56, accuracy: 0.02, "bottom edge alpha")
        XCTAssertEqual(pixels.at(1, pixels.height / 2).a, 0.56, accuracy: 0.02, "left edge at mid-height")
        XCTAssertEqual(pixels.at(midX, pixels.height / 2).a, 0, accuracy: 0.001, "the inside is clear")
        XCTAssertEqual(pixels.at(midX, 4).a, 0, accuracy: 0.001, "a 3 pt rail ends at 3 pt")
        XCTAssertEqual(pixels.at(0, 0).a, 0, accuracy: 0.001, "BUG-91's inner radius: the corner pixel is outside the rail")
    }

    func testTheTopCoverageMaskErasesTheSidesAndTheBottom() throws {
        // Subtle, Top: the band is opaque to 0.098 h and clear from 0.28 h.
        let pixels = try Pixels(XCTUnwrap(Cache.render(railKey(strength: 28, coverage: 0))))
        let midX = pixels.width / 2
        XCTAssertEqual(pixels.at(midX, 0).a, 0.35, accuracy: 0.02, "the top stop survives the mask")
        XCTAssertEqual(pixels.at(0, pixels.height / 2).a, 0, accuracy: 0.001, "no side rail at mid-height")
        XCTAssertEqual(pixels.at(midX, pixels.height - 1).a, 0, accuracy: 0.001, "no bottom rail")
        let fullBottom = try Pixels(XCTUnwrap(Cache.render(railKey(strength: 28, coverage: 1)))).at(midX, pixels.height - 1)
        XCTAssertGreaterThan(fullBottom.a, 0.2, "Full keeps the bottom (no mask)")
    }

    func testTheSheenFadesToClearByTwentyTwoPercentInsideTheShape() throws {
        let key = Key.sheen(size: poster, scale: 1, shape: inner8, sheen: 0.10)
        let pixels = try Pixels(XCTUnwrap(Cache.render(key)))
        let midX = pixels.width / 2
        XCTAssertEqual(pixels.at(midX, 0).a, 0.10, accuracy: 0.01)
        XCTAssertEqual(pixels.at(midX, Int(Double(pixels.height) * 0.11)).a, 0.05, accuracy: 0.01, "halfway down the fade")
        XCTAssertEqual(pixels.at(midX, Int(Double(pixels.height) * 0.30)).a, 0, accuracy: 0.001)
        XCTAssertEqual(pixels.at(0, 0).a, 0, accuracy: 0.001, "clipped to the rounded corner")
    }

    func testTheCircleRailIsARing() throws {
        let key = railKey(size: CGSize(width: 120, height: 120), shape: .circle, strength: 42)
        let pixels = try Pixels(XCTUnwrap(Cache.render(key)))
        XCTAssertGreaterThan(pixels.at(60, 1).a, 0.4, "the ring's top")
        XCTAssertEqual(pixels.at(1, 1).a, 0, accuracy: 0.001, "outside the circle")
        XCTAssertEqual(pixels.at(60, 60).a, 0, accuracy: 0.001, "inside the ring")
    }

    func testTheCacheReturnsOneBitmapPerKey() throws {
        let cache = CardDepthRasterCache()
        let subtle = try XCTUnwrap(cache.image(for: railKey(strength: 28)))
        XCTAssertTrue(subtle === cache.image(for: railKey(strength: 28)), "a hit returns the same bitmap")
        XCTAssertFalse(subtle === cache.image(for: railKey(strength: 42)), "another key renders its own")
        XCTAssertFalse(subtle === cache.image(for: railKey(shape: .circle)))
        cache.removeAll()
        XCTAssertFalse(subtle === cache.image(for: railKey(strength: 28)), "removeAll drops the bitmaps")
    }

    /// Reads a bitmap's pixels back as premultiplied RGBA, 0…1.
    private struct Pixels {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try XCTUnwrap(image.cgImage)
            let w = cgImage.width
            let h = cgImage.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
                guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            XCTAssertTrue(drawn)
            width = w
            height = h
            bytes = buffer
        }

        /// The pixel `x` across and `y` down from the top-left.
        func at(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let index = (y * width + x) * 4
            return (Double(bytes[index]) / 255, Double(bytes[index + 1]) / 255,
                    Double(bytes[index + 2]) / 255, Double(bytes[index + 3]) / 255)
        }
    }
}
