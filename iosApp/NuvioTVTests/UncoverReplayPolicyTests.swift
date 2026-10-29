import XCTest
@testable import NuvioTV

/// Batch N (BUG-188 follow-up; Steven rc9: an Up pressed during the collection pop is lost).
/// `UncoverReplayPolicy.decide` names the row to replay a viewer Up or Down to after it retired a
/// pop restore: the restore row's neighbour in the pressed direction, unless focus is already
/// there (the engine made the move) or the restore row is at the strip's edge.
final class UncoverReplayPolicyTests: XCTestCase {

    private let rows = ["a", "b", "c", "d"]

    private func decide(_ kind: ViewerInputKind, current: String?, restore: String?) -> String? {
        UncoverReplayPolicy.decide(kind: kind, currentRowKey: current, restoreRowKey: restore, rowKeys: rows)
    }

    func testUpGoesToTheRowAboveTheRestoreRow() {
        XCTAssertEqual(decide(.up, current: "c", restore: "c"), "b")
    }

    func testDownGoesToTheRowBelowTheRestoreRow() {
        XCTAssertEqual(decide(.down, current: "b", restore: "b"), "c")
    }

    func testTheEnginesWrongWayLandingStillReplaysTheUp() {
        // The rig log: restore row c, the engine lands on d after the viewer's Up.
        XCTAssertEqual(decide(.up, current: "d", restore: "c"), "b")
    }

    func testFocusAlreadyOnTheDestinationReplaysNothing() {
        XCTAssertNil(decide(.up, current: "b", restore: "c"))
        XCTAssertNil(decide(.down, current: "d", restore: "c"))
    }

    func testNoStripFocusAnchorsOnTheRestoreRow() {
        XCTAssertEqual(decide(.up, current: nil, restore: "c"), "b")
        XCTAssertEqual(decide(.down, current: nil, restore: "a"), "b")
    }

    func testUpOnTheFirstRowReplaysNothing() {
        XCTAssertNil(decide(.up, current: "a", restore: "a"))
    }

    func testDownOnTheLastRowReplaysNothing() {
        XCTAssertNil(decide(.down, current: "d", restore: "d"))
    }

    func testAnUnknownRestoreRowReplaysNothing() {
        XCTAssertNil(decide(.up, current: "b", restore: nil))
        XCTAssertNil(decide(.up, current: "b", restore: "zz"))
    }

    func testOnlyVerticalInputsReplay() {
        for kind in [ViewerInputKind.left, .right, .select, .menu, .playPause, .swipe] {
            XCTAssertNil(decide(kind, current: "b", restore: "b"))
        }
    }

    func testDownOnRowZeroAndUpOnTheLastRowStillMove() {
        XCTAssertEqual(decide(.down, current: "a", restore: "a"), "b")
        XCTAssertEqual(decide(.up, current: "d", restore: "d"), "c")
    }

    func testDownWithFocusParkedAboveStillReplaysBelowTheRestoreRow() {
        XCTAssertEqual(decide(.down, current: "a", restore: "b"), "c")
    }

    func testEmptyRowsReplayNothing() {
        XCTAssertNil(UncoverReplayPolicy.decide(kind: .up, currentRowKey: nil, restoreRowKey: "b", rowKeys: []))
    }
}
