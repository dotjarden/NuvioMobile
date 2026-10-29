import XCTest
@testable import NuvioTV

/// BUG-156 (P2; Steven, beta.19-rc3 follow-ups 2026-10-09 and 10-14): Classic Home's pop restore.
/// The pure half, `HomeReturnFocusMemory`: the per-row card memory, the origin a push records (and
/// when it records none), and the requests the pop's three rungs issue.
final class BatchAHomeReturnTests: XCTestCase {

    func testRemembersTheLastCardPerRow() {
        var memory = HomeReturnFocusMemory()
        memory.remember(rowKey: "r1", itemId: "a")
        memory.remember(rowKey: "r1", itemId: "b")
        memory.remember(rowKey: "r3", itemId: "z")
        XCTAssertEqual(memory.itemByRow["r1"], "b")
        XCTAssertEqual(memory.itemByRow["r3"], "z")
    }

    func testAPushFromARowRecordsThatRowAndItsCard() {
        var memory = HomeReturnFocusMemory()
        memory.remember(rowKey: "r3", itemId: "card2")
        memory.notePush(focusedRowKey: "r3", lastOwnedRowKey: "r3", sinceRowRelease: nil, heroFocused: false)
        XCTAssertEqual(memory.origin, HomeReturnFocusMemory.Origin(rowKey: "r3", itemId: "card2"))
    }

    func testTheOriginIsCapturedAtThePushNotAtThePop() {
        var memory = HomeReturnFocusMemory()
        memory.remember(rowKey: "r3", itemId: "card2")
        memory.notePush(focusedRowKey: "r3", lastOwnedRowKey: "r3", sinceRowRelease: nil, heroFocused: false)
        // A row report during the cover (a late focus event) must not redirect the restore.
        memory.remember(rowKey: "r3", itemId: "card9")
        memory.remember(rowKey: "r5", itemId: "x")
        XCTAssertEqual(memory.takeOrigin(), HomeReturnFocusMemory.Origin(rowKey: "r3", itemId: "card2"))
    }

    func testAPushFromTheHeroRecordsNoOrigin() {
        var memory = HomeReturnFocusMemory()
        memory.remember(rowKey: "r3", itemId: "card2")
        memory.notePush(focusedRowKey: nil, lastOwnedRowKey: "r3", sinceRowRelease: 5, heroFocused: true)
        XCTAssertNil(memory.origin, "native restoration owns the CTA; a row request would steal it")
        memory.notePush(focusedRowKey: "r3", lastOwnedRowKey: "r3", sinceRowRelease: nil, heroFocused: true)
        XCTAssertNil(memory.origin)
    }

    func testAReleaseThatBeatThePushStillCountsInsideTheGrace() {
        var memory = HomeReturnFocusMemory()
        memory.remember(rowKey: "r2", itemId: "c")
        memory.notePush(focusedRowKey: nil, lastOwnedRowKey: "r2", sinceRowRelease: 0.05, heroFocused: false)
        XCTAssertEqual(memory.origin, HomeReturnFocusMemory.Origin(rowKey: "r2", itemId: "c"))
        memory.notePush(focusedRowKey: nil, lastOwnedRowKey: "r2",
                        sinceRowRelease: HomeReturnFocusMemory.releaseGrace + 0.1, heroFocused: false)
        XCTAssertNil(memory.origin, "an old release is not this push's origin")
        memory.notePush(focusedRowKey: nil, lastOwnedRowKey: "r2", sinceRowRelease: nil, heroFocused: false)
        XCTAssertNil(memory.origin)
    }

    func testARowNeverFocusedRestoresWithoutACard() {
        var memory = HomeReturnFocusMemory()
        memory.notePush(focusedRowKey: "r4", lastOwnedRowKey: "r4", sinceRowRelease: nil, heroFocused: false)
        XCTAssertEqual(memory.origin, HomeReturnFocusMemory.Origin(rowKey: "r4", itemId: nil))
    }

    func testTakeOriginIsOncePerPush() {
        var memory = HomeReturnFocusMemory()
        memory.notePush(focusedRowKey: "r1", lastOwnedRowKey: "r1", sinceRowRelease: nil, heroFocused: false)
        XCTAssertNotNil(memory.takeOrigin())
        XCTAssertNil(memory.takeOrigin(), "a second pop without a push restores nothing")
    }

    func testTheRungsNameTheCardThenTheFirstCard() {
        let origin = HomeReturnFocusMemory.Origin(rowKey: "r3", itemId: "card2")
        XCTAssertEqual(HomeReturnFocusMemory.rungDelays.count, 3)
        for rung in 1...2 {
            let request = HomeReturnFocusMemory.request(for: origin, rung: rung, generation: rung)
            XCTAssertEqual(request.rowKey, "r3")
            XCTAssertEqual(request.itemId, "card2")
            XCTAssertFalse(request.forceFirst)
            XCTAssertEqual(PinnedRowFocusRequest.target(for: request, rowKey: "r3", firstId: "card0", remembered: nil),
                           "card2", "a Classic row (no strip memory) lands on the remembered card")
        }
        let last = HomeReturnFocusMemory.request(for: origin, rung: 3, generation: 9)
        XCTAssertNil(last.itemId)
        XCTAssertTrue(last.forceFirst)
        XCTAssertEqual(PinnedRowFocusRequest.target(for: last, rowKey: "r3", firstId: "card0", remembered: nil), "card0")
        XCTAssertNil(PinnedRowFocusRequest.target(for: last, rowKey: "r1", firstId: "card0", remembered: nil),
                     "another row ignores it")
        XCTAssertGreaterThan(HomeReturnFocusMemory.expiry, HomeReturnFocusMemory.rungDelays.last ?? 0)
    }
}
