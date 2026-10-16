import XCTest
@testable import NuvioTV

/// `NativePauseCardRule` (P4 B16): the native pause card's visibility decision.
final class NativePauseCardRuleTests: XCTestCase {
    private func visible(pausedSince: TimeInterval? = 100, now: TimeInterval = 101.5, barKnownHidden: Bool = true,
                         panelOpen: Bool = false, enabled: Bool = true, isPlayingPhase: Bool = true,
                         isRebuilding: Bool = false) -> Bool {
        NativePauseCardRule.visible(pausedSince: pausedSince, now: now, barKnownHidden: barKnownHidden,
                                    panelOpen: panelOpen, enabled: enabled, isPlayingPhase: isPlayingPhase,
                                    isRebuilding: isRebuilding)
    }

    func testHiddenBeforeTheDelay() {
        XCTAssertFalse(visible(now: 101.49))
    }

    func testVisibleAtTheDelayWithTheBarKnownHidden() {
        XCTAssertTrue(visible(now: 101.5))
        XCTAssertTrue(visible(now: 130))
    }

    /// [C-5]: no `visible=false` callback yet this pause = the bar may be up.
    func testHiddenWhileTheBarIsUnknownOrVisible() {
        XCTAssertFalse(visible(barKnownHidden: false))
    }

    func testHiddenWhenNotPaused() {
        XCTAssertFalse(visible(pausedSince: nil))
    }

    func testHiddenWhileThePanelIsOpen() {
        XCTAssertFalse(visible(panelOpen: true))
    }

    func testHiddenWhenTheSettingIsOff() {
        XCTAssertFalse(visible(enabled: false))
    }

    func testHiddenDuringARebuild() {
        XCTAssertFalse(visible(isRebuilding: true))
    }

    func testHiddenOutsideThePlayingPhase() {
        XCTAssertFalse(visible(isPlayingPhase: false))
    }

    func testDelayMatchesTheSpec() {
        XCTAssertEqual(NativePauseCardRule.delaySec, 1.5)
        XCTAssertTrue(NativePauseCardRule.supported)
    }
}
