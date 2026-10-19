import XCTest
@testable import NuvioTV

/// Batch M Wave 1 (BUG-187, Steven rc9: back from a cast member lands on Play): the meta adoption
/// rule that keeps the rows mounted across the reload, and the fallback restore's memory box.
@MainActor
final class DetailFocusReturnTests: XCTestCase {
    // MARK: DetailMetaAdoption

    /// The pop's reload emits `isLoading` with no meta first; a page that has one keeps it.
    func testLoadingEmissionKeepsTheMetaOnScreen() {
        XCTAssertTrue(DetailMetaAdoption.keepsCurrent(hasMeta: true, incomingMeta: false))
    }

    /// Review r1: a reload error with no meta keeps the page too (no full-page error over content).
    func testReloadErrorKeepsTheMetaOnScreen() {
        XCTAssertTrue(DetailMetaAdoption.keepsCurrent(hasMeta: true, incomingMeta: false))
    }

    /// A meta always lands.
    func testMetaAlwaysLands() {
        XCTAssertFalse(DetailMetaAdoption.keepsCurrent(hasMeta: true, incomingMeta: true))
    }

    /// A first load (nothing on screen yet) takes every emission: loading, meta and error.
    func testFirstLoadTakesEveryEmission() {
        XCTAssertFalse(DetailMetaAdoption.keepsCurrent(hasMeta: false, incomingMeta: false))
        XCTAssertFalse(DetailMetaAdoption.keepsCurrent(hasMeta: false, incomingMeta: true))
    }

    // MARK: DetailFocusMemory

    /// Push from a cast card (focus goes nil on the way out), pop: the card is the target, once.
    func testPushFromACardArmsItOnce() {
        let memory = DetailFocusMemory()
        memory.note(row: .cast, key: "3")
        memory.note(row: .cast, key: nil)
        memory.arm()
        let target = memory.takeArmedTarget()
        XCTAssertEqual(target?.row, .cast)
        XCTAssertEqual(target?.key, "3")
        XCTAssertNil(memory.takeArmedTarget(), "a later appearance without a new push restores nothing")
    }

    /// Focus moved to the hero (or an untracked row) before the page left: nothing to restore.
    func testClearForgetsTheCard() {
        let memory = DetailFocusMemory()
        memory.note(row: .moreLikeThis, key: "tt0111161")
        memory.clear()
        memory.arm()
        XCTAssertNil(memory.takeArmedTarget())
    }

    /// Review r1: the engine reports Play between `onDisappear` (arm) and `onAppear` (take);
    /// that report must not disarm or forget the card.
    func testClearWhileHiddenKeepsTheArmedCard() {
        let memory = DetailFocusMemory()
        memory.note(row: .cast, key: "3")
        memory.arm()
        XCTAssertFalse(memory.pageVisible)
        memory.clear()
        let target = memory.takeArmedTarget()
        XCTAssertTrue(memory.pageVisible)
        XCTAssertEqual(target?.row, .cast)
        XCTAssertEqual(target?.key, "3")
    }

    /// Once the page is visible again, a move to the hero forgets the card as before.
    func testClearAfterAppearanceForgetsTheCard() {
        let memory = DetailFocusMemory()
        memory.note(row: .logos, key: "1")
        memory.arm()
        _ = memory.takeArmedTarget()
        memory.clear()
        memory.arm()
        XCTAssertNil(memory.takeArmedTarget())
    }

    /// An appearance with nothing armed still marks the page visible.
    func testUnarmedAppearanceMarksThePageVisible() {
        let memory = DetailFocusMemory()
        memory.arm()
        XCTAssertNil(memory.takeArmedTarget())
        XCTAssertTrue(memory.pageVisible)
        memory.note(row: .cast, key: "0")
        memory.clear()
        memory.arm()
        XCTAssertNil(memory.takeArmedTarget())
    }

    /// The first appearance (no push yet) and a page that never touched a tracked row restore nothing.
    func testNothingArmedWithoutARememberedCard() {
        let memory = DetailFocusMemory()
        XCTAssertNil(memory.takeArmedTarget())
        memory.arm()
        XCTAssertNil(memory.takeArmedTarget())
    }

    /// A newer restore retires the older one's pending rungs.
    func testNewerRestoreRetiresTheOlder() {
        let memory = DetailFocusMemory()
        let first = memory.beginRestore()
        let second = memory.beginRestore()
        XCTAssertFalse(memory.isCurrent(first))
        XCTAssertTrue(memory.isCurrent(second))
    }

    // MARK: DetailFocusRestore

    func testTrackedRows() {
        for row in [DetailRowID.cast, .logos, .collection, .moreLikeThis] {
            XCTAssertTrue(DetailFocusRestore.tracks(row), "\(row)")
        }
        for row in [DetailRowID.episodes, .trailers, .parental, .comments, .about] {
            XCTAssertFalse(DetailFocusRestore.tracks(row), "\(row)")
        }
    }

    /// Forced rungs correct any other card; late rungs only pull focus back into the row.
    func testRungRule() {
        XCTAssertTrue(DetailFocusRestore.shouldApply(force: true, current: nil, target: "2"))
        XCTAssertTrue(DetailFocusRestore.shouldApply(force: true, current: "0", target: "2"))
        XCTAssertFalse(DetailFocusRestore.shouldApply(force: true, current: "2", target: "2"))
        XCTAssertTrue(DetailFocusRestore.shouldApply(force: false, current: nil, target: "2"))
        XCTAssertFalse(DetailFocusRestore.shouldApply(force: false, current: "0", target: "2"))
    }

    /// FEAT-79's rung ladder, retired after its last rung.
    func testRungsMatchFeat79() {
        XCTAssertEqual(DetailFocusRestore.rungs.map(\.delay), [0, 0.35, 0.8, 1.1])
        XCTAssertEqual(DetailFocusRestore.rungs.map(\.force), [true, true, false, false])
        XCTAssertGreaterThan(DetailFocusRestore.retireDelay, DetailFocusRestore.rungs.map(\.delay).max() ?? 0)
    }
}
