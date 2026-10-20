import XCTest
@testable import NuvioTV

/// Batch N (BUG-188 follow-up; Steven rc9: an Up pressed during the collection pop is lost).
/// `UncoverReplayPolicy.decide` names the row to replay a viewer Up or Down to after it retired a
/// pop restore, before the restore landed, after it landed, or while the pager was not back yet
/// (the anchor is then the restore's row because the strip owns no focus).
final class UncoverReplayPolicyTests: XCTestCase {

    private typealias Policy = UncoverReplayPolicy

    private let rows = ["a", "b", "c", "d"]
    private let press: TimeInterval = 100

    private func decide(_ kind: ViewerInputKind,
                        owns: Bool = true,
                        current: String? = "b",
                        restore: String? = "b",
                        rowKeys: [String]? = nil,
                        changedAt: TimeInterval? = nil) -> String? {
        Policy.decide(kind: kind, stripOwnsFocus: owns, currentRowKey: current, restoreRowKey: restore,
                      rowKeys: rowKeys ?? rows, pressAt: press, lastRowChangeAt: changedAt)
    }

    // After landing: the strip owns focus on the restored row.

    func testUpAfterLandingGoesToTheRowAbove() {
        XCTAssertEqual(decide(.up, changedAt: press - 0.04), "a")
    }

    func testDownAfterLandingGoesToTheRowBelow() {
        XCTAssertEqual(decide(.down, changedAt: press - 0.04), "c")
    }

    // Before landing: the engine owns no strip row yet, so the restore row anchors.

    func testUpBeforeLandingAnchorsOnTheRestoreRow() {
        XCTAssertEqual(decide(.up, owns: false, current: "d", restore: "c"), "b")
    }

    func testDownBeforeLandingAnchorsOnTheRestoreRow() {
        XCTAssertEqual(decide(.down, owns: false, current: nil, restore: "c"), "d")
    }

    func testTheStripOwningFocusAnchorsOnTheCurrentRowNotTheRestoreRow() {
        XCTAssertEqual(decide(.down, owns: true, current: "a", restore: "c"), "b")
    }

    // Bounds.

    func testUpOnRowZeroReplaysNothing() {
        XCTAssertNil(decide(.up, current: "a", restore: "a"))
    }

    func testDownOnTheLastRowReplaysNothing() {
        XCTAssertNil(decide(.down, current: "d", restore: "d"))
    }

    func testDownOnRowZeroAndUpOnTheLastRowStillMove() {
        XCTAssertEqual(decide(.down, current: "a", restore: "a"), "b")
        XCTAssertEqual(decide(.up, current: "d", restore: "d"), "c")
    }

    // The engine already moved.

    func testARowChangeRightAfterThePressIsTheEnginesMove() {
        XCTAssertNil(decide(.up, changedAt: press + 0.05))
        XCTAssertNil(decide(.down, changedAt: press))
        XCTAssertNil(decide(.up, changedAt: press + UncoverRestorePolicy.regrabDefer))
    }

    func testARowChangeBeforeThePressDoesNotCount() {
        XCTAssertEqual(decide(.up, changedAt: press - 0.001), "a")
        XCTAssertEqual(decide(.up, changedAt: nil), "a")
    }

    /// Batch N review r1: `decide` runs at the retire + `regrabDefer` (+ the pager poll), later than
    /// press + `regrabDefer`, so an engine move landing in between is still its answer to the press.
    func testARowChangeLongAfterThePressIsStillTheEnginesMove() {
        XCTAssertNil(decide(.up, changedAt: press + UncoverRestorePolicy.regrabDefer + 0.001))
        XCTAssertNil(decide(.down, changedAt: press + UncoverRestorePolicy.regrabDefer + 0.5))
        XCTAssertNil(decide(.up, owns: false, current: nil, restore: "c", changedAt: press + 1.1))
    }

    // Not owning focus, and pending.

    func testNotOwningFocusIgnoresAStaleCurrentRow() {
        XCTAssertEqual(decide(.up, owns: false, current: "d", restore: "b"), "a")
    }

    func testPendingWithNoRestoreRowReplaysNothing() {
        XCTAssertNil(decide(.up, owns: false, current: "b", restore: nil))
    }

    func testPendingWithAnUnknownRestoreRowReplaysNothing() {
        XCTAssertNil(decide(.down, owns: false, current: nil, restore: "zz"))
    }

    func testPendingWithNoRowsYetReplaysNothing() {
        XCTAssertNil(decide(.up, owns: false, current: nil, restore: "b", rowKeys: []))
    }

    func testOnlyUpAndDownReplay() {
        for kind: ViewerInputKind in [.left, .right, .select, .menu, .playPause, .swipe] {
            XCTAssertNil(decide(kind), "\(kind) must not replay")
        }
    }
}
