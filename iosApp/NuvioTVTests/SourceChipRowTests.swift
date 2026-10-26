import XCTest
@testable import NuvioTV

/// Stream picker A, P2 (`docs/stream-picker-addons-plan-2026-10-25.md` §2): the pure decisions
/// behind the source chips — the D-pad step with wrap, which error chips are dropped after the
/// fan-out, the chip label, and the two timing constants Android TV uses.
final class SourceChipRowTests: XCTestCase {

    private let ids = ["addon:comet", "addon:torrentio", "addon:aio"]

    func testRightStepsThroughTheChipsAndWrapsToAll() {
        XCTAssertEqual(SourceChipRow.step(from: nil, chipIds: ids, direction: .next), "addon:comet")
        XCTAssertEqual(SourceChipRow.step(from: "addon:comet", chipIds: ids, direction: .next), "addon:torrentio")
        XCTAssertNil(SourceChipRow.step(from: "addon:aio", chipIds: ids, direction: .next))
    }

    func testLeftWrapsFromAllToTheLastChip() {
        XCTAssertEqual(SourceChipRow.step(from: nil, chipIds: ids, direction: .previous), "addon:aio")
        XCTAssertNil(SourceChipRow.step(from: "addon:comet", chipIds: ids, direction: .previous))
        XCTAssertEqual(SourceChipRow.step(from: "addon:torrentio", chipIds: ids, direction: .previous), "addon:comet")
    }

    func testADroppedSelectionStepsFromAll() {
        XCTAssertEqual(SourceChipRow.step(from: "addon:gone", chipIds: ids, direction: .next), "addon:comet")
        XCTAssertEqual(SourceChipRow.step(from: "addon:gone", chipIds: ids, direction: .previous), "addon:aio")
    }

    func testNoChipsMeansAll() {
        XCTAssertNil(SourceChipRow.step(from: nil, chipIds: [], direction: .next))
        XCTAssertNil(SourceChipRow.step(from: "addon:comet", chipIds: [], direction: .previous))
    }

    func testOnlyFailedEmptyChipsAreDropped() {
        let chips = [
            SourceChip(id: "addon:comet", name: "Comet", count: 6, isLoading: false, error: nil),
            SourceChip(id: "addon:torrentio", name: "Torrentio", count: 0, isLoading: false, error: "HTTP 502"),
            SourceChip(id: "addon:aio", name: "AIO Streams", count: 3, isLoading: false, error: "timeout"),
            SourceChip(id: "addon:empty", name: "Empty", count: 0, isLoading: false, error: nil),
        ]
        XCTAssertEqual(SourceChipRow.chipsToDrop(chips), ["addon:torrentio"])
    }

    func testLabelOmitsTheCountWhileLoading() {
        let loading = SourceChip(id: "addon:comet", name: "Comet", count: 0, isLoading: true, error: nil)
        let done = SourceChip(id: "addon:comet", name: "Comet", count: 6, isLoading: false, error: nil)
        XCTAssertEqual(SourceChipRow.label(for: loading), "Comet")
        XCTAssertEqual(SourceChipRow.label(for: done), "Comet \u{00B7} 6")
    }

    func testAccessibilityLabelsSpellTheState() {
        let loading = SourceChip(id: "a", name: "Comet", count: 0, isLoading: true, error: nil)
        let failed = SourceChip(id: "a", name: "Comet", count: 0, isLoading: false, error: "HTTP 502")
        let failedWithStreams = SourceChip(id: "a", name: "Comet", count: 2, isLoading: false, error: "partial")
        let done = SourceChip(id: "a", name: "Comet", count: 6, isLoading: false, error: nil)
        let one = SourceChip(id: "a", name: "Comet", count: 1, isLoading: false, error: nil)
        XCTAssertEqual(SourceChipRow.accessibilityLabel(for: one), "Comet, 1 source")
        XCTAssertEqual(SourceChipRow.accessibilityLabel(for: loading), "Comet, loading")
        XCTAssertEqual(SourceChipRow.accessibilityLabel(for: failed), "Comet, failed")
        XCTAssertEqual(SourceChipRow.accessibilityLabel(for: failedWithStreams), "Comet, 2 sources")
        XCTAssertEqual(SourceChipRow.accessibilityLabel(for: done), "Comet, 6 sources")
    }

    func testThrottleAllowsOnePressPerInterval() {
        let throttle = ChipMoveThrottle()
        XCTAssertTrue(throttle.allows(now: 100))
        XCTAssertFalse(throttle.allows(now: 100.05))
        XCTAssertTrue(throttle.allows(now: 100.2))
    }

    func testAndroidTvTimings() {
        XCTAssertEqual(SourceChipRow.moveRepeatInterval, 0.112, accuracy: 0.0001)
        XCTAssertEqual(SourceChipRow.errorChipLinger, 1.6, accuracy: 0.0001)
    }

    func testFocusKeys() {
        XCTAssertEqual(SourceChipRow.key(for: "addon:comet"), "chip:addon:comet")
        XCTAssertNotEqual(SourceChipRow.allKey, SourceChipRow.refreshKey)
    }
}
