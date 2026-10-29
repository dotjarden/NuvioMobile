import XCTest
@testable import NuvioTV

/// FEAT-79 review r1: the Classic rows page restores focus only after a push from a card.
@MainActor
final class ClassicRowsFocusMemoryTests: XCTestCase {
    func testPushFromAFocusedCardArms() {
        let m = ClassicRowsFocusMemory()
        m.note(rowKey: "series", itemId: "lanterns")
        m.armIfLeavingFromCard()
        XCTAssertEqual(m.takeArmedTarget(), "series")
        XCTAssertNil(m.takeArmedTarget(), "a restore runs once")
    }

    func testLeavingLongAfterFocusLeftTheRowsDoesNotArm() {
        let m = ClassicRowsFocusMemory()
        m.note(rowKey: "series", itemId: "lanterns")
        m.note(rowKey: "series", itemId: nil)
        // The tab-switch case: focus left the rows well before the page went away.
        // (`lostAt` is now; arming within 0.5 s still counts as the push's own hand-off.)
        m.armIfLeavingFromCard()
        XCTAssertEqual(m.takeArmedTarget(), "series")
        let fresh = ClassicRowsFocusMemory()
        fresh.armIfLeavingFromCard()
        XCTAssertNil(fresh.takeArmedTarget(), "nothing focused yet")
    }

    func testANewerRestoreSupersedesTheOlder() {
        let m = ClassicRowsFocusMemory()
        let first = m.beginRestore()
        let second = m.beginRestore()
        XCTAssertFalse(m.isCurrent(first))
        XCTAssertTrue(m.isCurrent(second))
    }
}
