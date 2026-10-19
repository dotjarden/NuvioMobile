import XCTest
@testable import NuvioTV

/// BUG-191 (Steven rc9, No Zoom: a collection row's captions faded into the next page's top
/// feather): `StripGeometry.fitPageHeight(measured:page:focusLift:)`, the Batch F fit page. With
/// the zoom on it adds the lift above and below the row (2 × 20 = 40); with No Zoom (lift 0) it adds
/// the feather's own 24 pt band (`stageBottomGap`) instead of nothing. Both are capped at the fixed
/// page, and both round up to a whole point as the pager always did.
@MainActor
final class StripFitPageTests: XCTestCase {

    private let lift = Theme.Size.heroPinnedRowFocusLiftAllowance

    func testNoZoomAddsTheFeatherBand() {
        XCTAssertEqual(StripGeometry.stageBottomGap, 24)
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 300, page: 600, focusLift: 0), 324)
        // A collection row 12 pt shorter than a catalog row still clears the feather.
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 427.5, page: 600, focusLift: 0), 452)
    }

    func testZoomAddsTheLiftAboveAndBelow() {
        XCTAssertEqual(lift, 20)
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 300, page: 600, focusLift: lift), 340)
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 300.25, page: 600, focusLift: lift), 341)
    }

    func testBothAreCappedAtThePage() {
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 590, page: 600, focusLift: 0), 600)
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 590, page: 600, focusLift: lift), 600)
        XCTAssertEqual(StripGeometry.fitPageHeight(measured: 700, page: 600, focusLift: lift), 600)
    }

    /// Against the real geometry: every regime's fit page for a row shorter than the tallest one is
    /// measured + 24 (No Zoom) or measured + 40 (zoom), or the page when that is shorter.
    func testAgainstLiveGeometry() {
        for noZoom in [true, false] {
            for dp in [CGFloat(105), 126, 134, 154] {
                let width = dp * 220.0 / 126.0
                let g = StripGeometry.make(StripGeometry.Inputs(posterHeight: width * 1.5,
                                                                posterWidth: width,
                                                                titlesShown: true,
                                                                noZoom: noZoom,
                                                                titleHeight: 38,
                                                                folderCaptionHeight: 23,
                                                                synopsisLineHeight: 30))
                let measured = g.rowHeight - 60
                let extra: CGFloat = noZoom ? 24 : 40
                XCTAssertEqual(StripGeometry.fitPageHeight(measured: measured, page: g.pageHeight,
                                                           focusLift: g.focusLift),
                               min(g.pageHeight, (measured + extra).rounded(.up)),
                               "\(Int(dp)) dp noZoom=\(noZoom)")
            }
        }
    }
}
