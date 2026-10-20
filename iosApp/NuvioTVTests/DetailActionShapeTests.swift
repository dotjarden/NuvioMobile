import XCTest
@testable import NuvioTV

/// Batch M Wave 1 (FEAT-82, Steven rc9): the Detail action buttons follow Poster › Corners —
/// square only at Square (radius 0); Rounded (12) and Round (28) keep the capsule.
final class DetailActionShapeTests: XCTestCase {
    func testOnlySquareCornersSquareTheButtons() {
        XCTAssertTrue(DetailActionShape.isSquare(cornerRadius: 0))
        XCTAssertFalse(DetailActionShape.isSquare(cornerRadius: 12))
        XCTAssertFalse(DetailActionShape.isSquare(cornerRadius: 28))
    }

    /// The default poster style (no synced setting yet) keeps the capsule.
    func testDefaultStyleKeepsTheCapsule() {
        XCTAssertFalse(DetailActionShape.isSquare(cornerRadius: PosterStyle.default.cornerRadius))
    }
}

/// Batch P (FEAT-82 equal squares): the side is Play's measured height, and only square, icon-only
/// buttons with a measured side take it.
final class DetailActionSquareTests: XCTestCase {
    func testSquareSideNeedsAMeasuredPlay() {
        XCTAssertNil(DetailActionSquare.side(playHeight: 0))
        XCTAssertNil(DetailActionSquare.side(playHeight: 1))
        XCTAssertEqual(DetailActionSquare.side(playHeight: 72.4), 72)
        XCTAssertEqual(DetailActionSquare.side(playHeight: 72.6), 73)
    }

    func testOnlySquareIconButtonsApply() {
        XCTAssertTrue(DetailActionSquare.applies(isSquare: true, iconOnly: true, side: 72))
        XCTAssertFalse(DetailActionSquare.applies(isSquare: false, iconOnly: true, side: 72), "Rounded / Round keep capsules")
        XCTAssertFalse(DetailActionSquare.applies(isSquare: true, iconOnly: false, side: 72), "text labels keep their width")
        XCTAssertFalse(DetailActionSquare.applies(isSquare: true, iconOnly: true, side: nil), "no square before Play is measured")
    }

    /// Rounded (12) and Round (28) never reach the square path.
    func testRoundedAndRoundNeverSquare() {
        for radius: CGFloat in [12, 28] {
            XCTAssertFalse(DetailActionSquare.applies(isSquare: DetailActionShape.isSquare(cornerRadius: radius),
                                                      iconOnly: true, side: 72))
        }
    }
}
