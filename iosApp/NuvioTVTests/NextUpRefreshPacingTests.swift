import XCTest
@testable import NuvioTV

/// FEAT-85 review round 2 P3-3: the first Up Next refresh of a Home pipeline skips the debounce
/// (review P3-1); every later one waits the 1.5 s debounce; a teardown makes the next pipeline's
/// first refresh fast again.
final class NextUpRefreshPacingTests: XCTestCase {
    func testFirstRefreshOfAPipelineHasNoDebounce() {
        let pacing = NextUpRefreshPacing()
        XCTAssertNil(pacing.delayNanoseconds())
    }

    func testRefreshesAfterOneHasStartedAreDebounced() {
        var pacing = NextUpRefreshPacing()
        pacing.markStarted()
        XCTAssertEqual(pacing.delayNanoseconds(), 1_500_000_000)
        XCTAssertEqual(pacing.delayNanoseconds(), NextUpRefreshPacing.debounceNanoseconds)
    }

    /// The attach-time burst: several triggers before any refresh has started all stay on the
    /// fast path (each cancels the one before it); only a refresh that got past its wait turns the
    /// debounce on.
    func testABurstBeforeTheFirstRefreshStartsStaysFast() {
        let pacing = NextUpRefreshPacing()
        for _ in 0..<3 {
            XCTAssertNil(pacing.delayNanoseconds())
        }
        XCTAssertFalse(pacing.hasStarted)
    }

    func testResetMakesTheNextPipelineFastAgain() {
        var pacing = NextUpRefreshPacing()
        pacing.markStarted()
        pacing.reset()
        XCTAssertNil(pacing.delayNanoseconds())
        XCTAssertEqual(pacing, NextUpRefreshPacing())
    }
}
