import XCTest
@testable import NuvioTV

/// BUG-165: the Menu exit shield's armed window (the pure half of `MenuExitShield`).
final class MenuExitShieldTests: XCTestCase {
    func testUnarmedClaimsNothing() {
        XCTAssertFalse(MenuExitShieldRule.claims(armedAt: nil, now: 100))
    }

    func testClaimsInsideTheArmedWindow() {
        XCTAssertTrue(MenuExitShieldRule.claims(armedAt: 100, now: 100))
        XCTAssertTrue(MenuExitShieldRule.claims(armedAt: 100, now: 100.4))
        XCTAssertTrue(MenuExitShieldRule.claims(armedAt: 100, now: 100 + MenuExitShield.maxArmedSeconds - 0.01))
    }

    func testCeilingAndClockRollbackReleaseThePress() {
        XCTAssertFalse(MenuExitShieldRule.claims(armedAt: 100, now: 100 + MenuExitShield.maxArmedSeconds))
        XCTAssertFalse(MenuExitShieldRule.claims(armedAt: 100, now: 99.5))
    }

    func testCeilingIsShort() {
        // Long enough for a cover dismissal (≈0.4 s) plus a slow release; short enough that a host
        // that never disarms gets its Menu back well inside a viewer's patience.
        XCTAssertLessThanOrEqual(MenuExitShield.maxArmedSeconds, 3)
        XCTAssertGreaterThanOrEqual(MenuExitShield.maxArmedSeconds, 1)
    }
}
