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

    /// Without a live clock a viewer's move cannot be told from the engine's: the pre-rc11 hold,
    /// which is also what the defaults give.
    func testNoClockKeepsThePreRc11Hold() {
        XCTAssertEqual(DetailPopGate.decide(focusedRow: nil, focusedKey: nil, target: target,
                                            viewerInput: false, regrabs: 0, clockLive: false), .hold)
        XCTAssertEqual(DetailPopGate.decide(focusedRow: nil, focusedKey: nil, target: target, viewerInput: false), .hold)
    }

    /// Positions and inputs decide, never the order the reports came in.
    func testRegrabDecisionIgnoresCallOrder() {
        let inputs: [(DetailRowID?, String?, Bool, Int, Bool)] = [
            (.cast, "1", false, 0, true), (nil, nil, false, 0, true), (nil, nil, false, 3, true),
            (.logos, nil, true, 0, true), (nil, nil, false, 0, false),
        ]
        let decide = { (input: (DetailRowID?, String?, Bool, Int, Bool)) in
            DetailPopGate.decide(focusedRow: input.0, focusedKey: input.1, target: self.target,
                                 viewerInput: input.2, regrabs: input.3, clockLive: input.4)
        }
        XCTAssertEqual(inputs.map(decide), inputs.reversed().map(decide).reversed())
        XCTAssertEqual(inputs.map(decide), [.landed, .regrab, .hold, .release, .hold])
    }

    // MARK: Steven's rc11 pop, replayed (rig log 2026-10-21, `console-r0-debug.log`)

    /// Drives the gate and the box the way `DetailView.onChange(of: focusedRow)` does.
    private func report(_ row: DetailRowID?, old: DetailRowID?, at time: TimeInterval,
                        memory: DetailFocusMemory, clockLive: Bool) -> DetailPopGate.Decision {
        memory.popMoves += 1
        let decision = DetailPopGate.decide(focusedRow: row, focusedKey: row == target.row ? target.key : nil,
                                            target: target, viewerInput: false,
                                            regrabs: memory.popRegrabs, clockLive: clockLive)
        switch decision {
        case .landed:
            memory.noteLanding(at: time)
            memory.dropHeldFocusChange()
        case .hold:
            memory.noteStray(at: time)
            memory.holdFocusChange(old: old, new: row)
        case .regrab:
            memory.noteStray(at: time)
            memory.popRegrabs += 1
            memory.holdFocusChange(old: old, new: row)
        case .release:
            break
        }
        return decision
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
        let decision = DetailPopGate.decide(focusedRow: .logos, focusedKey: "1", target: studios,
                                            viewerInput: false, regrabs: 0, clockLive: true)
        XCTAssertEqual(decision, .landed)
        memory.noteLanding(at: 50.589)
        XCTAssertEqual(memory.popLandings, 1)
        XCTAssertEqual(memory.awayTime(at: 51.3), 0)
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
        memory.noteLanding(at: 10.5)
        memory.noteStray(at: 10.6)
        memory.popRegrabs = 2
        memory.goLive(target, startedAt: 20)
        XCTAssertEqual(memory.popRegrabs, 0)
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
