import XCTest
@testable import NuvioTV

/// BUG-200 (GitHub #9 item 1): the lift the Detail Cast avatar draws for itself
/// (`DetailLabelLift`). The default cell (Accent Focus Ring off, zoom on) is the only cell that
/// changed: there the `.borderless` button lifts only the photo inside the avatar circle, so the
/// avatar must wear the system lift itself. Every other cell must stay exactly what
/// `PlainLabelRing.lift` resolved before. (The studio chip stays on `PlainLabelRing.lift`: the
/// system lift measured ×1.19 on its 52 pt capsule, see `DetailLabelLift`.)
@MainActor
final class DetailLabelLiftTests: XCTestCase {
    private let cells: [(accent: Bool, noZoom: Bool)] = [(false, false), (true, false), (false, true), (true, true)]

    /// `.systemLift` exactly where `cardFocusButtonStyle()` (the default `lift: .card`) installs the
    /// bare `.borderless` style, and nowhere else: a custom style (ring, still) never carries a
    /// system effect, and a `.systemLift` there would be the only lift-less focus read.
    func testDefaultCellIsTheSystemLiftExactlyWhereTheButtonIsBorderless() {
        for cell in cells {
            let kind = CardButtonStyleKind.resolve(noZoomOnFocus: cell.noZoom, accentFocusRing: cell.accent, lift: .card)
            let lift = DetailLabelLift.lift(accentFocusRing: cell.accent, noZoomOnFocus: cell.noZoom)
            XCTAssertEqual(lift == .systemLift, kind == .borderless, "accent=\(cell.accent) noZoom=\(cell.noZoom)")
        }
        XCTAssertEqual(DetailLabelLift.lift(accentFocusRing: false, noZoomOnFocus: false), .systemLift)
    }

    /// Ring on and both No Zoom cells: byte-identical to the pre-BUG-200 resolver.
    func testRingAndNoZoomCellsAreUnchanged() {
        for cell in cells where cell.accent || cell.noZoom {
            XCTAssertEqual(DetailLabelLift.lift(accentFocusRing: cell.accent, noZoomOnFocus: cell.noZoom),
                           PlainLabelRing.lift(accentFocusRing: cell.accent, noZoomOnFocus: cell.noZoom),
                           "accent=\(cell.accent) noZoom=\(cell.noZoom)")
        }
        XCTAssertEqual(DetailLabelLift.lift(accentFocusRing: true, noZoomOnFocus: false), .manualScale)
        XCTAssertEqual(DetailLabelLift.lift(accentFocusRing: false, noZoomOnFocus: true), .still(ringed: false))
        XCTAssertEqual(DetailLabelLift.lift(accentFocusRing: true, noZoomOnFocus: true), .still(ringed: true))
    }

    /// The system lift composites into its own layer, so the default cell needs no `zIndex` bump
    /// (`liftedCastZIndex` / `liftedCompanyZIndex` already read `CardFocusMode.resolve`).
    func testDefaultCellDoesNotRaiseTheFocusedCard() {
        XCTAssertFalse(DetailLabelLift.lift(accentFocusRing: false, noZoomOnFocus: false).raisesFocusedCard)
        for cell in cells {
            XCTAssertEqual(DetailLabelLift.lift(accentFocusRing: cell.accent, noZoomOnFocus: cell.noZoom).raisesFocusedCard,
                           CardFocusMode.resolve(accentFocusRing: cell.accent, noZoomOnFocus: cell.noZoom).raisesFocusedCard,
                           "accent=\(cell.accent) noZoom=\(cell.noZoom)")
        }
    }

    /// The cast caption follows the lifted avatar in both zoom-on cells: `CardCaptionFocusDrop`
    /// pays its 20 pt (`Theme.Size.heroPinnedRowFocusLiftAllowance`) for `.systemLift` and
    /// `.manualScale` and nothing for `.still`, so the two zoom-on cells must resolve to one of the
    /// paying modes and the No Zoom cells to `.still`.
    func testCaptionDropsTwentyPointsInBothZoomOnCellsAndNeverInNoZoom() {
        XCTAssertEqual(Theme.Size.heroPinnedRowFocusLiftAllowance, 20)
        for cell in cells {
            let lift = DetailLabelLift.lift(accentFocusRing: cell.accent, noZoomOnFocus: cell.noZoom)
            switch lift {
            case .systemLift, .manualScale:
                XCTAssertFalse(cell.noZoom, "a zoom-on lift in a No Zoom cell: accent=\(cell.accent)")
            case .still:
                XCTAssertTrue(cell.noZoom, "no lift (so no caption drop) in a zoom-on cell: accent=\(cell.accent)")
            }
        }
    }
}
