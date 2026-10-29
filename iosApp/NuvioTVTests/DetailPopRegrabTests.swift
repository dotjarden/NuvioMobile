import XCTest
@testable import NuvioTV

/// BUG-194 (Steven rc11: "going back from an actor still takes two moves"). The rig logged the same
/// cast pop in his configuration and in the Batch P Wave 1 configuration: forced rungs at +17 and
/// +368 ms (inside the pop transition, neither sticks on its own turn), the card lands at ~570 ms,
/// the engine's late restoration puts focus on its default candidate (Play) ~30 ms later, and the
/// free rung at ~0.8 s pulls it back (`moves=3`, Play focused for ~230 ms: the second move). The
/// gate now re-grabs that stray at once while the viewer-input clock is live.
@MainActor
final class DetailPopRegrabTests: XCTestCase {
    private let target: (row: DetailRowID, key: String) = (.cast, "1")

    // MARK: DetailPopGate.decide

    /// No viewer input since the pop and a live clock: a move off the target is the engine's,
    /// re-grabbed whether or not the card has landed yet (Play, another row, outside the rows).
    func testStrayWithoutViewerInputIsRegrabbed() {
        XCTAssertEqual(DetailPopGate.decide(focusedRow: nil, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: 0, clockLive: true), .regrab)
        XCTAssertEqual(DetailPopGate.decide(focusedRow: .logos, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: 1, clockLive: true), .regrab)
        XCTAssertEqual(DetailPopGate.decide(focusedRow: .moreLikeThis, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: DetailPopGate.maxRegrabs - 1,
                                            clockLive: true), .regrab)
    }

    /// The viewer's own press or swipe still stands the restore down, re-grabs left or not.
    func testViewerInputStillReleases() {
        XCTAssertEqual(DetailPopGate.decide(focusedRow: nil, focusedKey: nil, target: target,
                                            viewerInput: true, regrabs: 0, clockLive: true), .release)
        XCTAssertEqual(DetailPopGate.decide(focusedRow: .cast, focusedKey: "1", target: target,
                                            viewerInput: true, regrabs: 0, clockLive: true), .release)
    }

    /// A landing on the target row is unchanged by the re-grab inputs.
    func testLandingIsUnchanged() {
        for clockLive in [false, true] {
            for regrabs in 0...DetailPopGate.maxRegrabs {
                XCTAssertEqual(DetailPopGate.decide(focusedRow: .cast, focusedKey: "1", target: target,
                                                    viewerInput: false, regrabs: regrabs, clockLive: clockLive),
                               .landed, "clock \(clockLive) regrabs \(regrabs)")
            }
        }
    }

    /// Past Home's limit the gate holds and the late rungs decide, so a stray that keeps coming
    /// back can never pin focus in a loop.
    func testRegrabLimitFallsBackToTheHold() {
        XCTAssertEqual(DetailPopGate.maxRegrabs, UncoverRestorePolicy.maxRegrabs(clockLive: true))
        XCTAssertEqual(DetailPopGate.maxRegrabs, 3)
        XCTAssertEqual(DetailPopGate.decide(focusedRow: nil, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: DetailPopGate.maxRegrabs,
                                            clockLive: true), .hold)
    }

    /// Without a live clock a viewer's move cannot be told from the engine's: the pre-rc11 hold. (No
    /// defaults on `decide`: every caller says whether the clock is live.)
    func testNoClockKeepsThePreRc11Hold() {
        XCTAssertEqual(DetailPopGate.decide(focusedRow: nil, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: 0, clockLive: false), .hold)
        XCTAssertEqual(DetailPopGate.decide(focusedRow: .logos, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: 2, clockLive: false), .hold)
    }

    // MARK: DetailPopGate.regrabStillWanted (review r3 P3-3)

    /// A scheduled re-grab acts only for the newest restore, while it is live, with no input since the pop.
    func testRegrabStillWantedOnlyForTheNewestLiveRestoreWithoutInput() {
        XCTAssertTrue(DetailPopGate.regrabStillWanted(current: true, restoreLive: true, inputSincePop: false))
        XCTAssertFalse(DetailPopGate.regrabStillWanted(current: false, restoreLive: true, inputSincePop: false), "a newer restore")
        XCTAssertFalse(DetailPopGate.regrabStillWanted(current: true, restoreLive: false, inputSincePop: false), "retired or ended")
        XCTAssertFalse(DetailPopGate.regrabStillWanted(current: true, restoreLive: true, inputSincePop: true), "the viewer acted")
        XCTAssertFalse(DetailPopGate.regrabStillWanted(current: false, restoreLive: false, inputSincePop: true))
    }

    /// The same rule against the box, as `regrabPopTarget` reads it on the next turn: the retire and
    /// a newer restore each stand a pending re-grab down.
    func testPendingRegrabStandsDownOnRetireOrANewerRestore() {
        let memory = DetailFocusMemory()
        func wanted(_ generation: Int, input: Bool = false) -> Bool {
            DetailPopGate.regrabStillWanted(current: memory.isCurrent(generation), restoreLive: memory.restoreLive,
                                            inputSincePop: input)
        }
        let first = memory.beginRestore()
        memory.goLive(target, startedAt: 10)
        XCTAssertTrue(wanted(first))
        XCTAssertFalse(wanted(first, input: true))
        memory.endRestore()
        XCTAssertFalse(wanted(first), "the retire / viewer end")
        let second = memory.beginRestore()
        memory.goLive(target, startedAt: 20)
        XCTAssertFalse(wanted(first), "an older restore's re-grab")
        XCTAssertTrue(wanted(second))
    }

    // MARK: Steven's rc11 pop, replayed (rig log 2026-10-21, `console-r0-debug.log`)

    /// Drives the box through `DetailFocusMemory.report`, the call `DetailView.onChange(of: focusedRow)`
    /// makes, so the move count, the stray clock, the held change and the re-grab budget are the
    /// view's own code (review r3 P3-3).
    private func report(_ row: DetailRowID?, old: DetailRowID?, at time: TimeInterval,
                        memory: DetailFocusMemory, clockLive: Bool, viewerInput: Bool = false) -> DetailPopGate.Decision {
        memory.report(row: row, old: old, target: target, viewerInput: viewerInput, clockLive: clockLive, at: time)
    }

    /// rc11 with the fix: the card lands at +569 ms, the engine's stray to Play at ~+600 ms is
    /// re-grabbed at once and lands a frame later; the free rung at +0.8 s then finds the card and
    /// applies nothing (no `force=0` line). Focus is off the card for one frame, not ~230 ms.
    func testRc11PopIsOneVisibleMoveWithTheRegrab() {
        let memory = DetailFocusMemory()
        let pop: TimeInterval = 100
        memory.goLive(target, startedAt: pop)
        // +17 / +368 ms: the forced rungs, inside the transition (no card focused yet).
        XCTAssertTrue(DetailFocusRestore.shouldApply(force: true, current: nil, target: "1"))
        let steps = [
            report(.cast, old: nil, at: pop + 0.569, memory: memory, clockLive: true),
            report(nil, old: .cast, at: pop + 0.600, memory: memory, clockLive: true),
            report(.cast, old: nil, at: pop + 0.617, memory: memory, clockLive: true),
        ]
        XCTAssertEqual(steps, [.landed, .regrab, .landed])
        XCTAssertEqual(memory.popMoves, 3)
        XCTAssertEqual(memory.popRegrabs, 1)
        XCTAssertEqual(memory.popLandings, 2)
        XCTAssertNil(memory.heldFocusChange, "the re-landing drops the held stray")
        XCTAssertEqual(memory.popLandedAt ?? 0, pop + 0.569, accuracy: 0.0001)
        XCTAssertEqual(memory.awayTime(at: pop + 1.3), 0.017, accuracy: 0.0005)
        // +0.8 s: the free rung finds the card focused.
        XCTAssertFalse(DetailFocusRestore.shouldApply(force: false, current: "1", target: "1"))
    }

    /// The pre-rc11 rule on the same run (what both configurations logged): the stray holds until
    /// the free rung at +835 ms finds the cast state nil and pulls focus back.
    func testRc11PopWithoutTheRegrabLeftPlayFocusedUntilTheFreeRung() {
        let memory = DetailFocusMemory()
        let pop: TimeInterval = 100
        memory.goLive(target, startedAt: pop)
        let landed = report(.cast, old: nil, at: pop + 0.569, memory: memory, clockLive: false)
        let stray = report(nil, old: .cast, at: pop + 0.600, memory: memory, clockLive: false)
        XCTAssertEqual(memory.heldFocusChange?.old, .cast)
        XCTAssertTrue(DetailFocusRestore.shouldApply(force: false, current: nil, target: "1"))
        let back = report(.cast, old: nil, at: pop + 0.840, memory: memory, clockLive: false)
        XCTAssertEqual([landed, stray, back], [.landed, .hold, .landed])
        XCTAssertEqual(memory.popRegrabs, 0)
        XCTAssertEqual(memory.awayTime(at: pop + 1.3), 0.240, accuracy: 0.0005)
    }

    /// The studios row (`moves=1` in both configurations): one landing, nothing away.
    func testStudiosPopStaysOneMove() {
        let memory = DetailFocusMemory()
        let studios: (row: DetailRowID, key: String) = (.logos, "1")
        memory.goLive(studios, startedAt: 50)
        let decision = memory.report(row: .logos, old: nil, target: studios, viewerInput: false,
                                     clockLive: true, at: 50.589)
        XCTAssertEqual(decision, .landed)
        XCTAssertEqual(memory.popLandings, 1)
        XCTAssertEqual(memory.popMoves, 1)
        XCTAssertEqual(memory.popRegrabs, 0)
        XCTAssertEqual(memory.awayTime(at: 51.3), 0)
    }

    // MARK: DetailFocusMemory.report (the view's bookkeeping, review r3 P3-3)

    /// Each decision leaves the box as the view expects: `.hold` and `.regrab` start the stray clock
    /// and keep the change for the replay (`.regrab` also spends the budget), `.landed` drops the
    /// held change, `.release` touches nothing but the move count.
    func testReportDoesTheBookkeepingPerDecision() {
        let memory = DetailFocusMemory()
        memory.goLive(target, startedAt: 10)
        XCTAssertEqual(report(.cast, old: nil, at: 10.5, memory: memory, clockLive: true), .landed)
        XCTAssertEqual(memory.popLandings, 1)
        XCTAssertNil(memory.heldFocusChange)
        XCTAssertEqual(report(nil, old: .cast, at: 10.6, memory: memory, clockLive: true), .regrab)
        XCTAssertEqual(memory.popRegrabs, 1)
        XCTAssertEqual(memory.popStrayAt ?? 0, 10.6, accuracy: 0.0001)
        XCTAssertEqual(memory.heldFocusChange?.old, .cast)
        XCTAssertNil(memory.heldFocusChange?.new)
        XCTAssertEqual(report(.cast, old: nil, at: 10.62, memory: memory, clockLive: true), .landed)
        XCTAssertNil(memory.heldFocusChange, "the re-landing drops the held stray")
        XCTAssertNil(memory.popStrayAt)
        XCTAssertEqual(memory.popMoves, 3)
        // Without a clock the same stray is held, not re-grabbed.
        XCTAssertEqual(report(.logos, old: .cast, at: 10.7, memory: memory, clockLive: false), .hold)
        XCTAssertEqual(memory.popRegrabs, 1)
        XCTAssertEqual(memory.heldFocusChange?.new, .logos)
        // Viewer input releases without starting a stray or spending a re-grab.
        let quiet = DetailFocusMemory()
        quiet.goLive(target, startedAt: 30)
        XCTAssertEqual(report(nil, old: nil, at: 30.2, memory: quiet, clockLive: true, viewerInput: true), .release)
        XCTAssertEqual(quiet.popMoves, 1)
        XCTAssertEqual(quiet.popRegrabs, 0)
        XCTAssertNil(quiet.popStrayAt)
        XCTAssertNil(quiet.heldFocusChange)
    }

    /// A stray that keeps coming back spends the three re-grabs, then the gate holds for the late
    /// rungs: the budget is spent by `report`, not by the caller.
    func testReportSpendsTheRegrabBudgetThenHolds() {
        let memory = DetailFocusMemory()
        memory.goLive(target, startedAt: 0)
        var decisions: [DetailPopGate.Decision] = []
        var time: TimeInterval = 0.5
        for _ in 0...DetailPopGate.maxRegrabs {
            decisions.append(report(.cast, old: nil, at: time, memory: memory, clockLive: true))
            decisions.append(report(nil, old: .cast, at: time + 0.03, memory: memory, clockLive: true))
            time += 0.1
        }
        XCTAssertEqual(decisions, [.landed, .regrab, .landed, .regrab, .landed, .regrab, .landed, .hold])
        XCTAssertEqual(memory.popRegrabs, DetailPopGate.maxRegrabs)
        XCTAssertEqual(memory.popMoves, 8)
        XCTAssertNotNil(memory.heldFocusChange, "the last stray is held for the late rungs")
    }

    // MARK: DetailFocusMemory away clock

    /// Before the first landing nothing visible moved off the card, so a stray starts no clock.
    func testAwayClockStartsOnlyAfterALanding() {
        let memory = DetailFocusMemory()
        memory.goLive(target, startedAt: 10)
        memory.noteStray(at: 10.4)
        XCTAssertNil(memory.popStrayAt)
        memory.noteLanding(at: 10.6)
        XCTAssertEqual(memory.awayTime(at: 11), 0)
        XCTAssertEqual(memory.popLandedAt ?? 0, 10.6, accuracy: 0.0001)
    }

    /// A stray still running counts up to `now`; a second stray in a row keeps the first stamp.
    func testAwayTimeCountsAStrayStillRunning() {
        let memory = DetailFocusMemory()
        memory.goLive(target, startedAt: 10)
        memory.noteLanding(at: 10.5)
        memory.noteStray(at: 10.6)
        memory.noteStray(at: 10.7)
        XCTAssertEqual(memory.awayTime(at: 10.9), 0.3, accuracy: 0.0001)
        memory.noteLanding(at: 11.0)
        memory.noteStray(at: 11.2)
        memory.noteLanding(at: 11.25)
        XCTAssertEqual(memory.awayTime(at: 12), 0.45, accuracy: 0.0001)
        XCTAssertEqual(memory.popLandings, 3)
        XCTAssertEqual(memory.popLandedAt ?? 0, 10.5, accuracy: 0.0001, "the first landing stays the landing")
    }

    func testGoLiveResetsTheRegrabBookkeeping() {
        let memory = DetailFocusMemory()
        memory.goLive(target, startedAt: 10)
        _ = report(.cast, old: nil, at: 10.5, memory: memory, clockLive: true)
        _ = report(nil, old: .cast, at: 10.6, memory: memory, clockLive: true)
        _ = report(nil, old: nil, at: 10.7, memory: memory, clockLive: true)
        XCTAssertEqual(memory.popRegrabs, 2)
        XCTAssertEqual(memory.popMoves, 3)
        memory.goLive(target, startedAt: 20)
        XCTAssertEqual(memory.popRegrabs, 0)
        XCTAssertEqual(memory.popMoves, 0)
        XCTAssertNil(memory.heldFocusChange)
        XCTAssertEqual(memory.popLandings, 0)
        XCTAssertNil(memory.popStrayAt)
        XCTAssertNil(memory.popLandedAt)
        XCTAssertEqual(memory.awayTime(at: 30), 0)
    }

    /// A re-grab scheduled for one restore never acts for a newer one.
    func testCurrentGenerationFollowsTheNewestRestore() {
        let memory = DetailFocusMemory()
        let first = memory.beginRestore()
        XCTAssertEqual(memory.currentGeneration, first)
        let second = memory.beginRestore()
        XCTAssertEqual(memory.currentGeneration, second)
        XCTAssertFalse(memory.isCurrent(first))
    }
}
