import XCTest
@testable import NuvioTV

/// beta.18 verdict (BUG-112 residue): the gate order and decline reasons of `HomeUpIntoHeroGate`.
final class HomeUpIntoHeroGateTests: XCTestCase {
    private let window: TimeInterval = 0.8

    private func eval(now: TimeInterval = 100, up: TimeInterval = 99.9, released: TimeInterval? = nil,
                      key: String? = "row", past: Bool = true, above: Bool = false) -> HomeUpIntoHeroGate.Verdict {
        HomeUpIntoHeroGate.evaluate(now: now, lastUpInputAt: up, lastRowReleasedAt: released,
                                    focusedRowKey: key, rowsScrolledPastTop: past,
                                    originHasRowAbove: above, window: window)
    }

    func testStampInsideWindowReveals() {
        XCTAssertEqual(eval(up: 99.5), .reveal)
    }

    func testStampOutsideWindowDeclinesStale() {
        XCTAssertEqual(eval(up: 98.0), .declined(reason: "staleInput sinceUp=2000"))
    }

    func testExactBoundaryIsStale() {
        // 100 - 99.2 is 0.7999… in binary; stamp at 0 and evaluate at exactly the window value so
        // `now - lastUpInputAt` is bit-identical to `window`.
        XCTAssertEqual(eval(now: 0.8, up: 0), .declined(reason: "staleInput sinceUp=800"))
    }

    func testReleaseInsideWindowWithoutFocusedRowKeyReveals() {
        XCTAssertEqual(eval(released: 99.8, key: nil), .reveal)
    }

    func testFocusedRowKeyWithoutReleaseStampReveals() {
        XCTAssertEqual(eval(released: nil, key: "genres"), .reveal)
    }

    func testNoRowOriginDeclinesWithNone() {
        XCTAssertEqual(eval(released: nil, key: nil), .declined(reason: "noRowOrigin sinceRelease=none"))
    }

    func testOldReleaseDeclinesWithMs() {
        XCTAssertEqual(eval(released: 98.0, key: nil), .declined(reason: "noRowOrigin sinceRelease=2000"))
    }

    func testNotPastTopDeclinesFirst() {
        XCTAssertEqual(eval(up: 50, released: nil, key: nil, past: false), .declined(reason: "notPastTop"))
    }

    /// 2026-10-17 (folder-return Up-skip): an origin with a row above waives the past-top check
    /// (the engine scrolls to the CTA before the gate runs), but still needs the Up input and the
    /// row origin.
    func testRowAboveWaivesNotPastTop() {
        XCTAssertEqual(eval(released: 99.9, key: nil, past: false, above: true), .reveal)
    }

    func testRowAboveStillNeedsFreshInput() {
        XCTAssertEqual(eval(up: 98.0, past: false, above: true), .declined(reason: "staleInput sinceUp=2000"))
    }

    func testRowAboveStillNeedsRowOrigin() {
        XCTAssertEqual(eval(released: nil, key: nil, past: false, above: true),
                       .declined(reason: "noRowOrigin sinceRelease=none"))
    }

    // MARK: isEngineSkip (review r1 P2-1)

    private func skip(now: TimeInterval = 100.1, gained: TimeInterval? = 100.0, released: TimeInterval? = 100.0,
                      owned: Bool = false, up: TimeInterval = 100.076, written: TimeInterval? = nil) -> Bool {
        HomeUpIntoHeroGate.isEngineSkip(now: now, heroGainedAt: gained, rowReleasedAt: released,
                                        rowStillOwned: owned, lastUpInputAt: up,
                                        programmaticHeroAt: written, window: window)
    }

    /// The device case: the row releases and the hero gains in one update, the press arrives 76 ms later.
    func testEngineSkipPressAfterGain() { XCTAssertTrue(skip()) }

    func testEngineSkipRowNotYetReleased() { XCTAssertTrue(skip(released: nil, owned: true)) }

    func testEngineSkipInputJustBeforeGain() { XCTAssertTrue(skip(up: 99.9)) }

    /// Menu to the top (BUG-27) writes the hero focus: never a skip, even right after an Up.
    func testProgrammaticHeroWriteIsNotASkip() { XCTAssertFalse(skip(written: 100.0)) }

    /// A hero focused earlier (the release long before) that now receives an Up.
    func testGainLongAfterReleaseIsNotASkip() { XCTAssertFalse(skip(released: 99.5)) }

    /// The engine's late pop landing on the CTA, then an Up 0.85 s later (past the window).
    func testUpWellAfterGainIsNotASkip() { XCTAssertFalse(skip(now: 100.86, up: 100.85)) }

    /// Review r2 (P3-2) boundaries: a slow swipe stamped 0.7 s after the gain still counts; a
    /// release 0.2 s away from the gain does not; an input 0.31 s BEFORE the gain does not.
    func testSlowSwipeAfterGainIsASkip() { XCTAssertTrue(skip(now: 100.75, up: 100.7)) }

    func testReleaseTwoTenthsFromGainIsNotASkip() { XCTAssertFalse(skip(released: 99.8)) }

    func testInputWellBeforeGainIsNotASkip() { XCTAssertFalse(skip(up: 99.69)) }

    func testNoUpInputIsNotASkip() { XCTAssertFalse(skip(up: -1)) }

    func testNoGainIsNotASkip() { XCTAssertFalse(skip(gained: nil)) }

    func testStaleGainIsNotASkip() { XCTAssertFalse(skip(now: 101.0)) }
}
