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
