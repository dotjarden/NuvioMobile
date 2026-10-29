import XCTest
@testable import NuvioTV

/// BUG-188 (Steven rc9; rig log 2026-10-19): ~40 ms after the pop restore landed, the device focus
/// engine parked focus on the row above's `UIKitFocusableFillerItem`, and the deferred re-grab left
/// it there ~195 ms, the landed card's single flicker. `UncoverRestorePolicy.regrabsImmediately`
/// decides when the re-grab skips `regrabDefer`; `isFocusableFiller` matches the private type.
final class UncoverRestoreImmediateTests: XCTestCase {

    private typealias Policy = UncoverRestorePolicy

    func testAFillerUnderAClosedGateRegrabsAtOnce() {
        XCTAssertTrue(Policy.regrabsImmediately(fillerFocused: true, gateClosed: true, viewerInputSinceLanding: false))
    }

    func testEveryOtherCaseKeepsTheDeferredRegrab() {
        // Not a filler (the tab bar, the folder's Edit band): the press may still be in flight.
        XCTAssertFalse(Policy.regrabsImmediately(fillerFocused: false, gateClosed: true, viewerInputSinceLanding: false))
        // The gate is open (an unlanded restore, or after its window).
        XCTAssertFalse(Policy.regrabsImmediately(fillerFocused: true, gateClosed: false, viewerInputSinceLanding: false))
        // The viewer pressed since the landing: their move, never pulled back at once.
        XCTAssertFalse(Policy.regrabsImmediately(fillerFocused: true, gateClosed: true, viewerInputSinceLanding: true))
        XCTAssertFalse(Policy.regrabsImmediately(fillerFocused: false, gateClosed: false, viewerInputSinceLanding: true))
    }

    func testTheFillerIsMatchedByItsTypeName() {
        XCTAssertTrue(Policy.isFocusableFiller(typeName: "UIKitFocusableFillerItem"))
        XCTAssertTrue(Policy.isFocusableFiller(typeName: "SwiftUI.UIKitFocusableFillerItem"))
        XCTAssertFalse(Policy.isFocusableFiller(typeName: "UIKitFocusableViewResponderItem"))
        XCTAssertFalse(Policy.isFocusableFiller(typeName: "-"))
    }

    /// The rig log's shape still decides a re-grab (the filler move came 40 ms after the landing,
    /// focus outside the strip, no viewer input), so the immediate path is reached from `.regrab`.
    func testTheRigLogMoveIsARegrab() {
        let target = Policy.Target(rowKey: "test-collection-1004", itemId: "test-folder-1004",
                                   requestedAt: 17.022, issuedAt: 17.047, landedAt: 17.611)
        let action = Policy.decide(target, key: nil, now: 17.664, viewerInputAt: 16.9, clockLive: true)
        guard case .regrab(_, "landing") = action else { return XCTFail("expected a re-grab, got \(action)") }
    }
}
