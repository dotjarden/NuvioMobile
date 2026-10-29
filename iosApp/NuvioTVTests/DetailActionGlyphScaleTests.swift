import UIKit
import XCTest
@testable import NuvioTV

/// FEAT-82: the Detail action row's icon-only glyphs are brought to one optical size.
final class DetailActionGlyphScaleTests: XCTestCase {
    func testMeasuredSymbolsLandOnTheSameOpticalSize() {
        for (symbol, size) in DetailActionGlyphScale.measured {
            XCTAssertEqual(size * DetailActionGlyphScale.scale(for: symbol), DetailActionGlyphScale.target,
                           accuracy: 0.001, symbol)
        }
    }

    func testTheRingedCheckmarkIsTheReferenceAndTheBareGlyphsGrow() {
        XCTAssertEqual(DetailActionGlyphScale.scale(for: DetailActionSymbol.watchedOff), 1, accuracy: 0.001)
        XCTAssertGreaterThan(DetailActionGlyphScale.scale(for: DetailActionSymbol.libraryAdd), 1)
        XCTAssertLessThan(DetailActionGlyphScale.scale(for: DetailActionSymbol.trailer), 1)
    }

    func testEveryFactorStaysWithinAVisibleButModestRange() {
        for symbol in DetailActionGlyphScale.measured.keys {
            let scale = DetailActionGlyphScale.scale(for: symbol)
            XCTAssertGreaterThanOrEqual(scale, 0.8, symbol)
            XCTAssertLessThanOrEqual(scale, 1.3, symbol)
        }
    }

    func testPlayAndUnknownSymbolsAreLeftAlone() {
        XCTAssertEqual(DetailActionGlyphScale.scale(for: DetailActionSymbol.play), 1)
        XCTAssertEqual(DetailActionGlyphScale.scale(for: "star.fill"), 1)
        XCTAssertEqual(DetailActionGlyphScale.scale(for: ""), 1)
    }

    // MARK: Coverage (review r3 P2-1): a glyph cannot ship unscaled

    /// Every secondary icon-only symbol the action row can draw has a table entry.
    func testEverySecondaryIconOnlySymbolHasATableEntry() {
        for symbol in DetailActionSymbol.secondary {
            XCTAssertNotNil(DetailActionGlyphScale.measured[symbol], "\(symbol) has no DetailActionGlyphScale entry")
        }
        XCTAssertEqual(Set(DetailActionSymbol.secondary).count, DetailActionSymbol.secondary.count, "duplicate in secondary")
    }

    /// The table holds nothing the row does not draw (a renamed symbol must not leave a stale entry).
    func testTheTableHasNoStaleEntries() {
        XCTAssertEqual(Set(DetailActionGlyphScale.measured.keys), Set(DetailActionSymbol.secondary))
        XCTAssertNil(DetailActionGlyphScale.measured[DetailActionSymbol.play], "Play is primary and never scaled")
    }

    /// Every name is a real SF Symbol (a typo would draw nothing and still pass the table checks).
    func testEveryActionSymbolIsARealSymbol() {
        for symbol in DetailActionSymbol.secondary + [DetailActionSymbol.play] {
            XCTAssertNotNil(UIImage(systemName: symbol), symbol)
        }
    }

    /// The glyphs still waiting for a number from the box (owner's R0 session: a resumable film for
    /// In Library on, a series with Shuffle off and on). When one is measured, put its
    /// optical size in `DetailActionGlyphScale.measured`, delete it from `unmeasured`, and from here.
    func testUnmeasuredSymbolsAreExactlyTheListedThree() {
        XCTAssertEqual(DetailActionGlyphScale.unmeasured, ["shuffle", "shuffle.circle.fill", "checkmark"])
    }

    /// Start Over was measured on the box on 2026-10-22 (26 pt box): it scales down a little.
    func testStartOverIsMeasuredAndScalesDown() {
        XCTAssertEqual(DetailActionGlyphScale.scale(for: DetailActionSymbol.startOver), 25.0 / 26.0, accuracy: 0.001)
    }

    /// An unmeasured entry is provisional: it carries the target (scale 1), so nothing is guessed.
    func testUnmeasuredSymbolsAreProvisionalAtScaleOne() {
        for symbol in DetailActionGlyphScale.unmeasured {
            XCTAssertNotNil(DetailActionGlyphScale.measured[symbol], symbol)
            XCTAssertEqual(DetailActionGlyphScale.measured[symbol], DetailActionGlyphScale.target, symbol)
            XCTAssertEqual(DetailActionGlyphScale.scale(for: symbol), 1, symbol)
        }
        XCTAssertTrue(DetailActionGlyphScale.unmeasured.isSubset(of: Set(DetailActionSymbol.secondary)))
    }
}
