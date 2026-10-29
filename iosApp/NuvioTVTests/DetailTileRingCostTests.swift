import XCTest
import SwiftUI
@testable import NuvioTV

/// Batch M Wave 1 (BUG-153, rc9 regression with the accent ring on): the pure halves of the cheaper
/// Detail tile ring — the gated row `zIndex` and the `debug.detailTileRingNoAnim` animation rule.
final class DetailTileRingCostTests: XCTestCase {
    /// `liftedCastZIndex`'s rule for the Trailers, Season and Episode rows: only a lift SwiftUI
    /// draws (ring with zoom on, either No Zoom cell) raises the focused tile; the system lift never
    /// flips `zIndex`, and an unfocused tile is never raised.
    func testRaisedZIndexFollowsRaisesFocusedCard() {
        for accent in [false, true] {
            for noZoom in [false, true] {
                let raises = CardFocusMode.resolve(accentFocusRing: accent, noZoomOnFocus: noZoom).raisesFocusedCard
                XCTAssertEqual(DetailTileFocus.raisedZIndex(isFocused: true, accentFocusRing: accent, noZoomOnFocus: noZoom),
                               raises ? 1 : 0, "accent=\(accent) noZoom=\(noZoom)")
                XCTAssertEqual(DetailTileFocus.raisedZIndex(isFocused: false, accentFocusRing: accent, noZoomOnFocus: noZoom), 0)
            }
        }
        XCTAssertEqual(DetailTileFocus.raisedZIndex(isFocused: true, accentFocusRing: false, noZoomOnFocus: false), 0)
    }

    /// Knob off: the tile animates exactly as before (0.15 s ease-out, nil under Reduce Motion).
    func testTileAnimationUnchangedWithKnobOff() {
        for accent in [false, true] {
            XCTAssertNotNil(DetailTileFocus.tileFocusAnimation(reduceMotion: false, accentFocusRing: accent, ringNoAnim: false))
            XCTAssertNil(DetailTileFocus.tileFocusAnimation(reduceMotion: true, accentFocusRing: accent, ringNoAnim: false))
        }
    }

    /// Knob on: only ring tiles snap; ring-off tiles keep their animation.
    func testNoAnimKnobSnapsOnlyRingTiles() {
        XCTAssertNil(DetailTileFocus.tileFocusAnimation(reduceMotion: false, accentFocusRing: true, ringNoAnim: true))
        XCTAssertNotNil(DetailTileFocus.tileFocusAnimation(reduceMotion: false, accentFocusRing: false, ringNoAnim: true))
    }
}
