import XCTest
import SwiftUI
@testable import NuvioTV

/// Batch G Wave 3 (Steven rc7): the pure halves of BUG-177 (Detail tiles' ring + depth), BUG-178
/// (the top scrim ramps with the dim) and BUG-179 (the biography teaser).
final class DetailTileFocusTests: XCTestCase {
    // MARK: BUG-177

    /// The relation BUG-108 pinned for `FolderTile`/`CastCard`, now for the three Detail tiles: they
    /// sit on the default `.card` button style, so in the one cell where that style takes the native
    /// lift away (`.ring`), the tile must draw its own (`.manualScale`) and must be on the ring path.
    func testRingCellIsWhereTheTileDrawsItsOwnLift() {
        for accent in [false, true] {
            for noZoom in [false, true] {
                let kind = CardButtonStyleKind.resolve(noZoomOnFocus: noZoom, accentFocusRing: accent, lift: .card)
                if kind == .ring {
                    XCTAssertTrue(DetailTileFocus.drawsOwnRing(accentFocusRing: accent))
                    XCTAssertEqual(PlainLabelRing.lift(accentFocusRing: accent, noZoomOnFocus: noZoom), .manualScale)
                }
            }
        }
    }

    /// Ring OFF keeps the old `TileFocusLift` path and the same button styles the `.plain` call
    /// sites had, in both zoom modes ("ring off and zoom off look as before").
    func testRingOffKeepsTheOldTreatmentAndButtonStyle() {
        XCTAssertFalse(DetailTileFocus.drawsOwnRing(accentFocusRing: false))
        for noZoom in [false, true] {
            XCTAssertEqual(CardButtonStyleKind.resolve(noZoomOnFocus: noZoom, accentFocusRing: false, lift: .card),
                           CardButtonStyleKind.resolve(noZoomOnFocus: noZoom, accentFocusRing: false, lift: .plain))
        }
    }

    /// The ring draws on a focused tile in both ring-on cells (the BUG-177 report), never unfocused.
    func testRingDrawsWhenFocusedInBothRingCells() {
        for noZoom in [false, true] {
            XCTAssertEqual(PlainLabelRing.resolve(accentFocusRing: true, noZoomOnFocus: noZoom, focused: true), .accent)
            XCTAssertNil(PlainLabelRing.resolve(accentFocusRing: true, noZoomOnFocus: noZoom, focused: false))
        }
    }

    /// The caption follows ring mode's manual lift by the same 20 pt as the system lift.
    func testCaptionDropsInRingMode() {
        XCTAssertEqual(CardFocusMode.resolve(accentFocusRing: true, noZoomOnFocus: false), .manualScale)
        XCTAssertEqual(CardFocusMode.resolve(accentFocusRing: false, noZoomOnFocus: false), .systemLift)
    }

    func testBandScaleReservesTheRingWidthOnEachEdge() {
        let width = Theme.Size.episodeWidth
        XCTAssertEqual(DetailTileFocus.bandScale(width) * width, width - 2 * ringWidth, accuracy: 0.001)
        XCTAssertEqual(DetailTileFocus.bandScale(0), 1)
    }

    func testRailColourSamplesOnlyWithToggleDepthAndArt() {
        XCTAssertTrue(DetailTileFocus.samplesRailColor(depthTakesPosterColor: true, depthEnabled: true, artworkURL: "https://x/y.jpg"))
        XCTAssertFalse(DetailTileFocus.samplesRailColor(depthTakesPosterColor: false, depthEnabled: true, artworkURL: "https://x/y.jpg"))
        XCTAssertFalse(DetailTileFocus.samplesRailColor(depthTakesPosterColor: true, depthEnabled: false, artworkURL: "https://x/y.jpg"))
        XCTAssertFalse(DetailTileFocus.samplesRailColor(depthTakesPosterColor: true, depthEnabled: true, artworkURL: nil))
        XCTAssertFalse(DetailTileFocus.samplesRailColor(depthTakesPosterColor: true, depthEnabled: true, artworkURL: ""))
    }

    // MARK: BUG-178

    func testTopScrimRampsWithTheDim() {
        XCTAssertEqual(DetailDim.topScrimOpacity(dim: 0), 0)
        XCTAssertEqual(DetailDim.topScrimOpacity(dim: 0.15), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DetailDim.topScrimOpacity(dim: DetailDim.topScrimFullDim), 1, accuracy: 0.0001)
        XCTAssertEqual(DetailDim.topScrimOpacity(dim: DetailDim.ceiling), 1)
    }

    func testTopScrimSteppedKnobIsTheOldOnOff() {
        XCTAssertEqual(DetailDim.topScrimOpacity(dim: 0, stepped: true), 0)
        XCTAssertEqual(DetailDim.topScrimOpacity(dim: 0.05, stepped: true), 1)
    }

    // MARK: BUG-179

    func testBioTruncationNeedsBothMeasurements() {
        XCTAssertFalse(PersonBioTeaser.isTruncated(fullHeight: 0, shownHeight: 200))
        XCTAssertFalse(PersonBioTeaser.isTruncated(fullHeight: 400, shownHeight: 0))
    }

    func testBioTruncationIgnoresSubPointRounding() {
        XCTAssertFalse(PersonBioTeaser.isTruncated(fullHeight: 240.6, shownHeight: 240))
        XCTAssertTrue(PersonBioTeaser.isTruncated(fullHeight: 300, shownHeight: 240))
    }
}
