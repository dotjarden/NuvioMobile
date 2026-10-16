import XCTest
@testable import NuvioTV

/// BUG-156 (a) + (b) (Steven, beta.19-rc4 verdict 2026-10-16: the return from a collection, and from a
/// movie inside a collection, still jumps): the strip's pop-restore decisions
/// (`UncoverRestorePolicy`) and the folder Rows page's push origin (`FolderPushOrigin`).
final class UncoverRestorePolicyTests: XCTestCase {

    private typealias Policy = UncoverRestorePolicy

    /// Popped at 10.0, request out at 10.2.
    private func target(landedAt: TimeInterval? = nil, regrabs: Int = 0) -> Policy.Target {
        Policy.Target(rowKey: "r3", itemId: "card2", requestedAt: 10.0, issuedAt: 10.2,
                      landedAt: landedAt, regrabs: regrabs)
    }

    // MARK: Landing

    func testTheFirstTargetRowChangeIsTheLanding() {
        XCTAssertEqual(Policy.decide(target(), key: "r3", now: 10.6, viewerInputAt: nil, clockLive: true), .land)
        XCTAssertEqual(Policy.decide(target(landedAt: 10.6), key: "r3", now: 11.0, viewerInputAt: nil, clockLive: true), .keep,
                       "back on the target after a landing (a re-grab landing) changes nothing")
    }

    // MARK: The engine's late restoration

    /// The device pass: our rung lands at +0.56 s, the engine moves focus 35 ms later.
    func testAnEngineMoveRightAfterTheLandingRegrabs() {
        let action = Policy.decide(target(landedAt: 10.56), key: "r2", now: 10.595, viewerInputAt: nil, clockLive: true)
        guard case .regrab(let age, let from) = action else { return XCTFail("expected a re-grab, got \(action)") }
        XCTAssertEqual(age, 0.035, accuracy: 0.0001)
        XCTAssertEqual(from, "landing")
    }

    /// Steven's case: the engine's move came more than 1.2 s after the REQUEST, which the old rule
    /// took for the viewer's. Counted from the landing, it is still the engine's.
    func testALateMoveIsMeasuredFromTheLandingNotTheRequest() {
        let now = 10.2 + 1.4   // 1.4 s after the request (old rule: expired)
        let action = Policy.decide(target(landedAt: 10.9), key: "r2", now: now, viewerInputAt: nil, clockLive: true)
        guard case .regrab(let age, "landing") = action else { return XCTFail("expected a re-grab, got \(action)") }
        XCTAssertEqual(age, 0.7, accuracy: 0.0001)
    }

    func testAMovePastTheLandedWindowExpires() {
        let landed = 10.6
        XCTAssertEqual(Policy.decide(target(landedAt: landed), key: "r2", now: landed + Policy.landedWindow + 0.01,
                                     viewerInputAt: nil, clockLive: true), .retire("expired"))
    }

    /// The target never landed: the old request-age rule stands.
    func testAnUnlandedRestoreKeepsTheRequestAgeRule() {
        let early = Policy.decide(target(), key: "r1", now: 10.2 + 1.0, viewerInputAt: nil, clockLive: true)
        guard case .regrab(_, "request") = early else { return XCTFail("expected a re-grab from the request, got \(early)") }
        XCTAssertEqual(Policy.decide(target(), key: "r1", now: 10.2 + Policy.unlandedWindow + 0.01,
                                     viewerInputAt: nil, clockLive: true), .retire("expired"))
    }

    /// Focus leaving the strip (the tab bar, the folder's Edit band) with no viewer input is the
    /// engine's default candidate too.
    func testLeavingTheStripWithNoInputRegrabs() {
        let action = Policy.decide(target(landedAt: 10.6), key: nil, now: 11.2, viewerInputAt: nil, clockLive: true)
        guard case .regrab = action else { return XCTFail("expected a re-grab, got \(action)") }
    }

    // MARK: The second move

    /// Classic's device walk saw the engine fire twice; with the clock live, up to three re-grabs.
    func testWithTheClockSeveralEngineMovesRegrabUpToTheLimit() {
        let limit = Policy.maxRegrabs(clockLive: true)
        XCTAssertEqual(limit, 3)
        let second = Policy.decide(target(landedAt: 10.6, regrabs: 1), key: "r2", now: 11.0, viewerInputAt: nil, clockLive: true)
        guard case .regrab = second else { return XCTFail("a second engine move must re-grab with the clock live: \(second)") }
        XCTAssertEqual(Policy.decide(target(landedAt: 10.6, regrabs: limit), key: "r2", now: 11.0,
                                     viewerInputAt: nil, clockLive: true), .retire("limit"))
    }

    /// Without the clock nothing tells the engine from the viewer: a second move is the viewer's.
    func testWithoutTheClockASecondMoveIsTheViewers() {
        XCTAssertEqual(Policy.maxRegrabs(clockLive: false), 1)
        let first = Policy.decide(target(landedAt: 10.6), key: "r2", now: 11.0, viewerInputAt: nil, clockLive: false)
        guard case .regrab = first else { return XCTFail("the first move re-grabs: \(first)") }
        XCTAssertEqual(Policy.decide(target(landedAt: 10.6, regrabs: 1), key: "r4", now: 11.2,
                                     viewerInputAt: nil, clockLive: false), .retire("limit"))
    }

    // MARK: The viewer's own input retires

    func testAViewerInputAfterThePopRetires() {
        XCTAssertEqual(Policy.decide(target(landedAt: 10.6), key: "r4", now: 10.9, viewerInputAt: 10.85, clockLive: true),
                       .retire("viewer"))
        XCTAssertEqual(Policy.decide(target(), key: "r3", now: 10.9, viewerInputAt: 10.5, clockLive: true),
                       .retire("viewer"), "even a move onto the target row is the viewer's once they pressed")
        XCTAssertTrue(Policy.viewerMoved(target(), viewerInputAt: 10.0), "an input at the pop itself counts")
    }

    /// The Menu press that popped began before the pop edge: it never retires the restore.
    func testThePopPressItselfIsNotAViewerMove() {
        let action = Policy.decide(target(landedAt: 10.6), key: "r2", now: 10.9, viewerInputAt: 9.7, clockLive: true)
        guard case .regrab = action else { return XCTFail("the Menu that popped must not count: \(action)") }
        XCTAssertFalse(Policy.viewerMoved(target(), viewerInputAt: nil))
    }

    // MARK: FolderPushOrigin

    private typealias Origin = FolderPushOrigin.Origin

    func testAStripStillHoldingFocusIsTheOrigin() {
        let current = Origin(rowKey: "tab2", itemId: "tt2")
        XCTAssertEqual(FolderPushOrigin.resolve(current: current, lost: Origin(rowKey: "tab1", itemId: "x"),
                                                sinceLoss: 0.4, inputBeforeLoss: ("up", 3), clockLive: true,
                                                railArmedSinceLoss: true), current)
    }

    /// The usual push: Select on a card, Detail takes focus, the strip reports the loss, the page
    /// disappears at the end of the push transition.
    func testASelectThenALossIsThePush() {
        let lost = Origin(rowKey: "tab2", itemId: "tt2")
        XCTAssertEqual(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: 0.5,
                                                inputBeforeLoss: ("select", 0.05), clockLive: true,
                                                railArmedSinceLoss: false), lost)
        // A hold menu's "Go to Details": the loss came with the menu, long before the disappear.
        XCTAssertEqual(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: 6,
                                                inputBeforeLoss: ("select", 0.8), clockLive: true,
                                                railArmedSinceLoss: false), lost)
    }

    /// Up to the Edit band (then Edit Filters), Left into the rail: no origin, the page's own focus.
    func testALossAfterADirectionalPressIsNotAPush() {
        let lost = Origin(rowKey: "tab1", itemId: "tt1")
        XCTAssertNil(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: 0.4,
                                              inputBeforeLoss: ("up", 0.02), clockLive: true, railArmedSinceLoss: false))
        XCTAssertNil(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: 0.4,
                                              inputBeforeLoss: ("select", 0.02), clockLive: true, railArmedSinceLoss: true),
                     "a tab picked in the rail is the rail route's to restore")
        XCTAssertNil(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: 0.4,
                                              inputBeforeLoss: ("select", 5), clockLive: true, railArmedSinceLoss: false),
                     "a Select long before the loss did not cause it")
        XCTAssertNil(FolderPushOrigin.resolve(current: nil, lost: nil, sinceLoss: nil,
                                              inputBeforeLoss: nil, clockLive: true, railArmedSinceLoss: false))
    }

    /// Without the clock: a loss inside the grace before the disappear.
    func testWithoutTheClockTheLossGraceDecides() {
        let lost = Origin(rowKey: "tab1", itemId: nil)
        XCTAssertEqual(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: 0.6, inputBeforeLoss: nil,
                                                clockLive: false, railArmedSinceLoss: false), lost)
        XCTAssertNil(FolderPushOrigin.resolve(current: nil, lost: lost, sinceLoss: FolderPushOrigin.lossGrace + 0.1,
                                              inputBeforeLoss: nil, clockLive: false, railArmedSinceLoss: false))
    }
}
