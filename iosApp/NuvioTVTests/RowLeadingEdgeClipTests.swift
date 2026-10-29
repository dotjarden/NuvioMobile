import XCTest
@testable import NuvioTV

/// BUG-92 / BUG-164: the leading-edge allowance a catalog row opens for its first card
/// (`RowLeadingEdgeClip.rowAllowance`), and the trailer tile's lift style (`CardSystemLiftStyle`).
final class RowLeadingEdgeClipTests: XCTestCase {
    private let rise = Theme.Size.heroPinnedRowFocusLiftAllowance

    /// The zoom-on formula `CatalogRowView.leadingEdgeAllowance` inlined before BUG-164, kept here
    /// verbatim as the baseline the zoom-on branch must reproduce to the bit.
    private func preBug164ZoomOn(restingWidth: CGFloat, artworkHeight: CGFloat, accent: Bool) -> CGFloat {
        let posterWidth = max(restingWidth, artworkHeight * 16 / 9)
        let liftScale = 1 + 2 * rise / artworkHeight
        return RowLeadingEdgeClip.allowance(posterWidth: posterWidth, liftScale: liftScale,
                                            ringWidth: accent ? ringWidth : 0)
    }

    func testZoomOnIsByteIdenticalToTheOldFormula() {
        let shapes: [(CGFloat, CGFloat)] = [
            (Theme.Size.landscapeWidth, Theme.Size.landscapeHeight),
            (220, 330), (183, 274.5), (268.9, 403.3), (500, 281), (720, 300),
        ]
        for (w, h) in shapes {
            for accent in [false, true] {
                XCTAssertEqual(RowLeadingEdgeClip.rowAllowance(noZoomOnFocus: false, accentFocusRing: accent,
                                                               restingWidth: w, artworkHeight: h, liftRise: rise),
                               preBug164ZoomOn(restingWidth: w, artworkHeight: h, accent: accent),
                               "w=\(w) h=\(h) accent=\(accent)")
            }
        }
    }

    func testZoomOnPinnedValues() {
        // The 16:9 tile's half lift growth is 16/9·h × 20/h = 35.6 pt at every height → 36 + 22.
        XCTAssertEqual(RowLeadingEdgeClip.rowAllowance(noZoomOnFocus: false, accentFocusRing: false,
                                                       restingWidth: 220, artworkHeight: 330, liftRise: 20), 58)
        XCTAssertEqual(RowLeadingEdgeClip.rowAllowance(noZoomOnFocus: false, accentFocusRing: true,
                                                       restingWidth: 220, artworkHeight: 330, liftRise: 20), 62)
        XCTAssertEqual(RowLeadingEdgeClip.rowAllowance(noZoomOnFocus: false, accentFocusRing: false,
                                                       restingWidth: 360, artworkHeight: 203, liftRise: 20), 58)
    }

    func testNoZoomOpensForTheShadowsVisibleReach() {
        // BUG-164: was ring 4 + radius 22 = 26, which cut the still focus shadow at 7 % darkness.
        XCTAssertEqual(RowLeadingEdgeClip.shadowReach(), 44)
        for accent in [false, true] {
            for (w, h) in [(CGFloat(220), CGFloat(330)), (360, 203), (268.9, 403.3)] {
                XCTAssertEqual(RowLeadingEdgeClip.rowAllowance(noZoomOnFocus: true, accentFocusRing: accent,
                                                               restingWidth: w, artworkHeight: h, liftRise: rise), 44)
            }
        }
    }

    func testNoZoomNeverOpensLessThanTheOldRingPlusRadius() {
        XCTAssertGreaterThan(RowLeadingEdgeClip.shadowReach(),
                             ringWidth + RowLeadingEdgeClip.cardShadowRadius)
    }

    func testTileLiftStyleOnlyWithZoomOnInPortraitRows() {
        XCTAssertEqual(CardSystemLiftStyle.resolve(tileShowing: true, landscapeRow: false, noZoomOnFocus: false), .lift)
        // BUG-164: No Zoom never lifts the tile.
        XCTAssertEqual(CardSystemLiftStyle.resolve(tileShowing: true, landscapeRow: false, noZoomOnFocus: true), .highlight)
        for noZoom in [false, true] {
            XCTAssertEqual(CardSystemLiftStyle.resolve(tileShowing: true, landscapeRow: true, noZoomOnFocus: noZoom), .highlight)
            XCTAssertEqual(CardSystemLiftStyle.resolve(tileShowing: false, landscapeRow: false, noZoomOnFocus: noZoom), .highlight)
        }
    }
}
