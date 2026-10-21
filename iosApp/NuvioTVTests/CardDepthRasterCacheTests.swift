import XCTest
import SwiftUI
@testable import NuvioTV

/// W3-13 (UX-16 / BUG-153 remainder): the white-rail × tint identity. The rail now strokes white at
/// the stop alphas and takes the poster colour by `.colorMultiply`, which must paint what
/// `railColor(tint).opacity(stop)` painted at every stop (`CardDepthStyle.multipliedRailStop` vs
/// `tintedRailStop`, the latter checked against SwiftUI's own colour resolution).
@MainActor
final class CardDepthRasterCacheTests: XCTestCase {

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
}
