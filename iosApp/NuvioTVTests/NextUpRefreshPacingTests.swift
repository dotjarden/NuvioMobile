import XCTest
@testable import NuvioTV

/// FEAT-85 review P3-1 / pass 3 P3-3: the ordering rule of Home's Up Next refresh scheduling
/// (`NextUpRefreshScheduler`, which `HomeViewModel.scheduleNextUpRefresh` calls). The first
/// refresh of a pipeline runs right after the triggers queued behind it on the main queue (the
/// watchers' attach-time replays), once; later ones wait the debounce and coalesce; a reset makes
/// the next pipeline's first refresh fast again. The debounce is shortened to keep the run quick.
@MainActor
final class NextUpRefreshPacingTests: XCTestCase {
    private let debounce: UInt64 = 300_000_000 // 0.3 s
    private let short: UInt64 = 60_000_000     // well inside the debounce
    private let long: UInt64 = 700_000_000     // well past it

    private final class Counter { var runs = 0 }

    private func makeScheduler(_ counter: Counter) -> NextUpRefreshScheduler {
        NextUpRefreshScheduler(debounceNanoseconds: debounce) { counter.runs += 1 }
    }

    /// The attach-time burst: one trigger, then replays queued FIFO on the main queue behind it.
    /// Each replay cancels the refresh before it, and exactly one refresh runs, without waiting
    /// the debounce.
    func testFirstRefreshRunsOnceRightAfterTheQueuedReplays() async {
        let counter = Counter()
        let scheduler = makeScheduler(counter)
        scheduler.schedule()
        for _ in 0..<3 {
            DispatchQueue.main.async { scheduler.schedule() }
        }
        XCTAssertEqual(counter.runs, 0, "nothing runs synchronously")
        try? await Task.sleep(nanoseconds: short)
        XCTAssertEqual(counter.runs, 1, "one refresh, before the debounce would have elapsed")
        try? await Task.sleep(nanoseconds: long)
        XCTAssertEqual(counter.runs, 1, "the cancelled ones never run")
    }

    /// After a refresh has run, triggers wait the debounce and a burst of them runs once.
    func testLaterRefreshesAreDebouncedAndCoalesce() async {
        let counter = Counter()
        let scheduler = makeScheduler(counter)
        scheduler.schedule()
        try? await Task.sleep(nanoseconds: short)
        XCTAssertEqual(counter.runs, 1)

        for _ in 0..<3 { scheduler.schedule() }
        try? await Task.sleep(nanoseconds: short)
        XCTAssertEqual(counter.runs, 1, "still inside the debounce")
        try? await Task.sleep(nanoseconds: long)
        XCTAssertEqual(counter.runs, 2, "the burst ran once, after the debounce")
    }

    /// A pipeline teardown cancels the pending refresh and makes the next first refresh fast.
    func testResetCancelsThePendingRefreshAndRestoresTheFastPath() async {
        let counter = Counter()
        let scheduler = makeScheduler(counter)
        scheduler.schedule()
        try? await Task.sleep(nanoseconds: short)
        XCTAssertEqual(counter.runs, 1)

        scheduler.schedule() // debounced
        scheduler.reset()
        try? await Task.sleep(nanoseconds: long)
        XCTAssertEqual(counter.runs, 1, "the pending refresh was cancelled")

        scheduler.schedule()
        try? await Task.sleep(nanoseconds: short)
        XCTAssertEqual(counter.runs, 2, "the next pipeline's first refresh is immediate again")
    }

    func testPacingIsFastUntilARefreshStarts() {
        var pacing = NextUpRefreshPacing()
        XCTAssertNil(pacing.delayNanoseconds())
        pacing.markStarted()
        XCTAssertNotNil(pacing.delayNanoseconds())
        pacing.reset()
        XCTAssertNil(pacing.delayNanoseconds())
    }
}
