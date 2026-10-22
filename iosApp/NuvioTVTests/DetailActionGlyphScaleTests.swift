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
        XCTAssertEqual(DetailActionGlyphScale.scale(for: "checkmark.circle"), 1, accuracy: 0.001)
        XCTAssertGreaterThan(DetailActionGlyphScale.scale(for: "plus"), 1)
        XCTAssertLessThan(DetailActionGlyphScale.scale(for: "play.rectangle.fill"), 1)
    }

    func testEveryFactorStaysWithinAVisibleButModestRange() {
        for symbol in DetailActionGlyphScale.measured.keys {
            let scale = DetailActionGlyphScale.scale(for: symbol)
            XCTAssertGreaterThanOrEqual(scale, 0.8, symbol)
            XCTAssertLessThanOrEqual(scale, 1.3, symbol)
        }
    }

    func testUnknownSymbolsAreLeftAlone() {
        XCTAssertEqual(DetailActionGlyphScale.scale(for: "play.fill"), 1)
        XCTAssertEqual(DetailActionGlyphScale.scale(for: "shuffle"), 1)
        XCTAssertEqual(DetailActionGlyphScale.scale(for: ""), 1)
    }
}
