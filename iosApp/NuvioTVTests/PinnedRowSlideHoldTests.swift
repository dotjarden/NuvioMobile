import XCTest
import CoreGraphics
@testable import NuvioTV

/// beta.18 verdict (BUG-87/89, R1) — the pinned title's slide hold is released by the settle
/// corrector's rest DECISION, not by its own wall clock. Pure-value tests, like
/// `PinnedRowSettleRc14Tests`: the verdict `commitSlide` switches on, the rest-decision observer
/// registry, the reason the decision line carries, and the timing invariants between the hold's
/// clocks and the corrector's. W3-14 (BUG-209) adds the focused row's in-band exemption: the
/// `.track` verdict, its guards (focused, in band, no hold running) and `slideInBand`.
@MainActor
final class PinnedRowSlideHoldTests: XCTestCase {

    // MARK: - slideHoldVerdict

    /// The verdict with the W3-14 (BUG-209) inputs spelled out. The defaults describe the row the
    /// pre-W3-14 rule covered whole: unfocused, out of band, no hold running.
    private func verdict(target: CGFloat, current: CGFloat, moving: Bool, pending: Bool,
                         focused: Bool = false, inBand: Bool = false,
                         holding: Bool = false) -> PinnedRowTitle.SlideHoldVerdict {
        PinnedRowTitle.slideHoldVerdict(target: target, current: current,
                                        moving: moving, restPending: pending,
                                        focused: focused, inBand: inBand, holding: holding)
    }

    func testZeroTargetWhileMovingSnaps() {
        XCTAssertEqual(verdict(target: 0, current: 8, moving: true, pending: false), .snapToZero)
        XCTAssertEqual(verdict(target: 0, current: 8, moving: true, pending: true), .snapToZero)
    }

    func testZeroTargetAtRestEases() {
        // A pending decision never holds a 0 target: 0 is never wrong for a contained title.
        XCTAssertEqual(verdict(target: 0, current: 8, moving: false, pending: false), .apply)
        XCTAssertEqual(verdict(target: 0, current: 8, moving: false, pending: true), .apply)
    }

    func testZeroTargetAlreadyAtZeroIsAPlainApply() {
        XCTAssertEqual(verdict(target: 0, current: 0, moving: false, pending: false), .apply)
        XCTAssertEqual(verdict(target: 0, current: 0, moving: true, pending: false), .apply)
    }

    /// W3-14 (BUG-209): the 0-target snap is untouched — it wins over the focused in-band
    /// exemption in every combination, so a title leaving the clip edge still snaps home.
    func testZeroTargetIgnoresTheFocusedInBandExemption() {
        for focused in [false, true] {
            for inBand in [false, true] {
                for holding in [false, true] {
                    let label = "focused=\(focused) inBand=\(inBand) holding=\(holding)"
                    XCTAssertEqual(verdict(target: 0, current: 8, moving: true, pending: true,
                                           focused: focused, inBand: inBand, holding: holding),
                                   .snapToZero, label)
                    XCTAssertEqual(verdict(target: 0, current: 8, moving: false, pending: true,
                                           focused: focused, inBand: inBand, holding: holding),
                                   .apply, label)
                    XCTAssertEqual(verdict(target: 0, current: 0, moving: true, pending: false,
                                           focused: focused, inBand: inBand, holding: holding),
                                   .apply, label)
                }
            }
        }
    }

    /// The hold as beta.18 built it, now for every row the W3-14 exemption does not cover: an
    /// unfocused row (in band or not) and a focused row out of band wait while the rows move OR a
    /// decision is pending.
    func testNonzeroTargetHoldsWhileMovingOrPending() {
        let nonExempt: [(focused: Bool, inBand: Bool)] = [(false, false), (false, true), (true, false)]
        for row in nonExempt {
            let label = "focused=\(row.focused) inBand=\(row.inBand)"
            XCTAssertEqual(verdict(target: 8, current: 0, moving: true, pending: false,
                                   focused: row.focused, inBand: row.inBand), .hold, label)
            XCTAssertEqual(verdict(target: 8, current: 0, moving: false, pending: true,
                                   focused: row.focused, inBand: row.inBand), .hold, label)
            XCTAssertEqual(verdict(target: 8, current: 0, moving: true, pending: true,
                                   focused: row.focused, inBand: row.inBand), .hold, label)
        }
    }

    func testNonzeroTargetAtDecidedRestApplies() {
        for focused in [false, true] {
            for inBand in [false, true] {
                for holding in [false, true] {
                    XCTAssertEqual(verdict(target: 8, current: 0, moving: false, pending: false,
                                           focused: focused, inBand: inBand, holding: holding),
                                   .apply, "focused=\(focused) inBand=\(inBand) holding=\(holding)")
                }
            }
        }
    }

    // MARK: - W3-14 (BUG-209): the focused row's in-band slide

    /// The matrix: focused/unfocused × in/out of band × moving/pending, no hold running. Only the
    /// focused in-band row changes: it tracks while moving, and eases at rest without waiting for
    /// the decision.
    func testFocusedInBandMatrix() {
        struct Case { let focused: Bool; let inBand: Bool; let moving: Bool; let pending: Bool
                      let expected: PinnedRowTitle.SlideHoldVerdict }
        let cases: [Case] = [
            // Focused, in band: the exemption.
            Case(focused: true, inBand: true, moving: true, pending: false, expected: .track),
            Case(focused: true, inBand: true, moving: true, pending: true, expected: .track),
            Case(focused: true, inBand: true, moving: false, pending: true, expected: .apply),
            Case(focused: true, inBand: true, moving: false, pending: false, expected: .apply),
            // Focused, out of band: beta.18's hold (a nudge may come).
            Case(focused: true, inBand: false, moving: true, pending: false, expected: .hold),
            Case(focused: true, inBand: false, moving: true, pending: true, expected: .hold),
            Case(focused: true, inBand: false, moving: false, pending: true, expected: .hold),
            Case(focused: true, inBand: false, moving: false, pending: false, expected: .apply),
            // Unfocused, in band: rc14's hold (the row a nudge or a departing scroll carries).
            Case(focused: false, inBand: true, moving: true, pending: false, expected: .hold),
            Case(focused: false, inBand: true, moving: true, pending: true, expected: .hold),
            Case(focused: false, inBand: true, moving: false, pending: true, expected: .hold),
            Case(focused: false, inBand: true, moving: false, pending: false, expected: .apply),
            // Unfocused, out of band: unchanged.
            Case(focused: false, inBand: false, moving: true, pending: false, expected: .hold),
            Case(focused: false, inBand: false, moving: true, pending: true, expected: .hold),
            Case(focused: false, inBand: false, moving: false, pending: true, expected: .hold),
            Case(focused: false, inBand: false, moving: false, pending: false, expected: .apply),
        ]
        for c in cases {
            XCTAssertEqual(verdict(target: 10.5, current: 4, moving: c.moving, pending: c.pending,
                                   focused: c.focused, inBand: c.inBand),
                           c.expected,
                           "focused=\(c.focused) inBand=\(c.inBand) moving=\(c.moving) pending=\(c.pending)")
        }
    }

    /// A hold episode already running (it started out of band — an Up approach coming down from
    /// above the clip edge) keeps the release path even once its target reaches the band:
    /// tracking from the stale slide would pop the title down by the whole band in one frame.
    func testFocusedInBandKeepsARunningHold() {
        XCTAssertEqual(verdict(target: 10, current: 0, moving: true, pending: false,
                               focused: true, inBand: true, holding: true), .hold)
        XCTAssertEqual(verdict(target: 10, current: 0, moving: true, pending: true,
                               focused: true, inBand: true, holding: true), .hold)
        XCTAssertEqual(verdict(target: 10, current: 0, moving: false, pending: true,
                               focused: true, inBand: true, holding: true), .hold)
        XCTAssertEqual(verdict(target: 10, current: 0, moving: false, pending: false,
                               focused: true, inBand: true, holding: true), .apply)
    }

    /// Steven's Down, reading by reading (`P351c0p1r0z0t38hzrt4`: rest −10.52, `clearance.focused`
    /// 10): the incoming focused row's slide is 0 below the clip edge, then tracks every reading of
    /// the reveal's last ~10pt, and never holds — so the settle decision has nothing to release.
    func testStevensDownTracksEveryReadingToTheRest() {
        let clearances = PinnedRowTitle.Clearances(atRest: 30, focused: 10, lift: 20, focusedRaw: 10)
        var current: CGFloat = 0
        for target: CGFloat in [0, 0, 1.5, 4, 7, 9, 10, 10.524] {
            let inBand = PinnedRowTitle.slideInBand(target: target, clearances: clearances)
            XCTAssertTrue(inBand, "every slide on the way to the rest is in band (\(target))")
            let v = verdict(target: target, current: current, moving: true, pending: true,
                            focused: true, inBand: inBand, holding: false)
            XCTAssertEqual(v, target == 0 ? .apply : .track, "target \(target)")
            current = target
        }
        XCTAssertEqual(current, 10.524, accuracy: 0.001, "the title lands on the rest with the posters")
    }

    // MARK: - SlideHoldDecision.exempt (review r1 P3-5, r2 P3-2)

    /// The probe's `exempt=` flag is the decision's own: true exactly when the W3-14 focused
    /// in-band exemption produced the verdict (a nonzero target, focused, in band, no hold running),
    /// across the whole input space, and the verdict is `slideHoldVerdict`'s whatever the flag.
    func testExemptIsTheFocusedInBandRuleAcrossEveryInput() {
        var exemptCount = 0
        for target: CGFloat in [0, 1.5, 10.5, 72] {
            for current: CGFloat in [0, 4] {
                for moving in [false, true] {
                    for pending in [false, true] {
                        for focused in [false, true] {
                            for inBand in [false, true] {
                                for holding in [false, true] {
                                    let label = "target=\(target) current=\(current) moving=\(moving) pending=\(pending) "
                                        + "focused=\(focused) inBand=\(inBand) holding=\(holding)"
                                    let decision = PinnedRowTitle.slideHoldDecision(
                                        target: target, current: current, moving: moving, restPending: pending,
                                        focused: focused, inBand: inBand, holding: holding)
                                    XCTAssertEqual(decision.exempt, target != 0 && focused && inBand && !holding, label)
                                    XCTAssertEqual(decision.verdict,
                                                   verdict(target: target, current: current, moving: moving,
                                                           pending: pending, focused: focused, inBand: inBand,
                                                           holding: holding), label)
                                    if decision.exempt {
                                        exemptCount += 1
                                        XCTAssertEqual(decision.verdict, moving ? .track : .apply, label)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(exemptCount, 0, "the exemption is reachable")
    }

    /// The two ends the flag distinguishes in the log: Steven's focused in-band Down is exempt
    /// whether the rows move or rest; the unfocused neighbour, the out-of-band row, a running hold
    /// and the 0-target snap are not.
    func testExemptMarksOnlyTheFocusedInBandRowWithNoHoldRunning() {
        // `current` is off 0 so a 0 target has a title to snap home.
        func decision(target: CGFloat = 8, moving: Bool = true, focused: Bool = true, inBand: Bool = true,
                      holding: Bool = false) -> PinnedRowTitle.SlideHoldDecision {
            PinnedRowTitle.slideHoldDecision(target: target, current: 4, moving: moving, restPending: true,
                                             focused: focused, inBand: inBand, holding: holding)
        }
        XCTAssertEqual(decision(), .init(verdict: .track, exempt: true))
        XCTAssertEqual(decision(moving: false), .init(verdict: .apply, exempt: true))
        XCTAssertEqual(decision(focused: false), .init(verdict: .hold, exempt: false))
        XCTAssertEqual(decision(inBand: false), .init(verdict: .hold, exempt: false))
        XCTAssertEqual(decision(holding: true), .init(verdict: .hold, exempt: false))
        XCTAssertEqual(decision(target: 0), .init(verdict: .snapToZero, exempt: false))
        XCTAssertEqual(decision(target: 0, moving: false), .init(verdict: .apply, exempt: false))
    }

    // MARK: - slideInBand

    func testSlideInBandIsTheCorrectorsLowEdgeWithItsSlack() {
        XCTAssertEqual(PinnedRowTitle.slideBandSlack, 2)
        let clearances = PinnedRowTitle.Clearances(atRest: 30, focused: 10, lift: 20, focusedRaw: 10)
        XCTAssertTrue(PinnedRowTitle.slideInBand(target: 0, clearances: clearances))
        XCTAssertTrue(PinnedRowTitle.slideInBand(target: 10, clearances: clearances))
        // Steven's held rest: −10.52 against bandLo −10 — in band only through the slack, exactly
        // as the corrector reads it (`PinnedRowGeometryTests.testMediumPlusPanelHeldSpendsOnlyTheHoldOvershoot`).
        XCTAssertTrue(PinnedRowTitle.slideInBand(target: 10.524, clearances: clearances))
        XCTAssertTrue(PinnedRowTitle.slideInBand(target: 12, clearances: clearances), "boundary is inside")
        XCTAssertFalse(PinnedRowTitle.slideInBand(target: 12.01, clearances: clearances))
        XCTAssertFalse(PinnedRowTitle.slideInBand(target: 72, clearances: clearances))
    }

    func testSlideInBandJudgesTheLiftedClearanceNotTheRestingOne() {
        // An unfocused row's resting clearance is larger; the exemption is judged on the focused
        // (lifted) one, which is what the tracked title actually rides over.
        let clearances = PinnedRowTitle.Clearances(atRest: 30, focused: 10, lift: 20, focusedRaw: 10)
        XCTAssertFalse(PinnedRowTitle.slideInBand(target: 20, clearances: clearances))
        // A lift-deficit row (focused clamped at 0) is in band only within the slack.
        let deficit = PinnedRowTitle.Clearances(atRest: 12, focused: 0, lift: 30, focusedRaw: -18)
        XCTAssertTrue(PinnedRowTitle.slideInBand(target: 2, clearances: deficit))
        XCTAssertFalse(PinnedRowTitle.slideInBand(target: 3, clearances: deficit))
    }

    // MARK: - Rest-decision observers

    func testRestDecisionBroadcastsToEveryRegisteredRow() {
        var calledA = 0
        var calledB = 0
        let keyA = "test.slideHold.a.\(UUID().uuidString)"
        let keyB = "test.slideHold.b.\(UUID().uuidString)"
        let tokenA = PinnedRowSettle.observeRestDecision(rowKey: keyA) { calledA += 1 }
        let tokenB = PinnedRowSettle.observeRestDecision(rowKey: keyB) { calledB += 1 }
        defer {
            PinnedRowSettle.stopObservingRestDecision(rowKey: keyA, token: tokenA)
            PinnedRowSettle.stopObservingRestDecision(rowKey: keyB, token: tokenB)
        }

        // The host app may have live titles registered too, so the count is asserted as a delta.
        let both = PinnedRowSettle.notifyRestDecided(reason: "clean")
        XCTAssertEqual(calledA, 1)
        XCTAssertEqual(calledB, 1)
        XCTAssertGreaterThanOrEqual(both, 2)

        PinnedRowSettle.stopObservingRestDecision(rowKey: keyA, token: tokenA)
        let one = PinnedRowSettle.notifyRestDecided(reason: "clean")
        XCTAssertEqual(calledA, 1, "a stopped observer must not be called")
        XCTAssertEqual(calledB, 2)
        XCTAssertEqual(one, both - 1)
    }

    func testStaleTokenDoesNotUnregisterTheReplacement() {
        var calledOld = 0
        var calledNew = 0
        let key = "test.slideHold.remount.\(UUID().uuidString)"
        let oldToken = PinnedRowSettle.observeRestDecision(rowKey: key) { calledOld += 1 }
        // A `.id()` remount registers the incoming title before the outgoing one tears down.
        let newToken = PinnedRowSettle.observeRestDecision(rowKey: key) { calledNew += 1 }
        defer { PinnedRowSettle.stopObservingRestDecision(rowKey: key, token: newToken) }
        PinnedRowSettle.stopObservingRestDecision(rowKey: key, token: oldToken)

        PinnedRowSettle.notifyRestDecided(reason: "clean")
        XCTAssertEqual(calledOld, 0)
        XCTAssertEqual(calledNew, 1)
    }

    // MARK: - restDecisionReason

    func testRestDecisionReasonFromReports() {
        XCTAssertEqual(PinnedRowSettle.restDecisionReason(report: "row=x margin=-8 nudge=0"), "clean")
        XCTAssertEqual(PinnedRowSettle.restDecisionReason(report: "row=x margin=-8 nudge=0 topRest=1"), "topRest")
        XCTAssertEqual(PinnedRowSettle.restDecisionReason(report: "row=x margin=-90 nudge=0 room=12"), "room")
        XCTAssertEqual(PinnedRowSettle.restDecisionReason(report: "row=- state=nofocus y=120 seq=3"), "nofocus")
        XCTAssertEqual(PinnedRowSettle.restDecisionReason(report: "row=x clearance=30 nudge=0 standDown=lift-deficit"),
                       "standdown")
    }

    // MARK: - Clock invariants

    func testFallbackOutlastsTheCorrectorsDecisionAndNudge() {
        // A decision that is coming (settle at settleDelay, plus a nudge's own nudgeDuration) must
        // always beat the wall-clock fallback, or the title lands before the nudge again.
        XCTAssertGreaterThan(PinnedRowTitle.slideHoldMax,
                             PinnedRowSettle.settleDelay + PinnedRowSettle.nudgeDuration)
    }

    func testCeilingOutlastsTheFallback() {
        XCTAssertLessThan(PinnedRowTitle.slideHoldMax, PinnedRowTitle.slideHoldCeiling)
    }

    func testMotionWindowIsShorterThanTheFallback() {
        XCTAssertLessThan(PinnedRowTitle.slideMotionHold, PinnedRowTitle.slideHoldMax)
    }
}
