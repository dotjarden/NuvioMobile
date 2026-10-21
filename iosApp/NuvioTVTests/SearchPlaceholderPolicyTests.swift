import XCTest
@testable import NuvioTV

final class SearchPlaceholderPolicyTests: XCTestCase {
    func testStartsVisibleAndHidesOnceWithTheFirstReason() {
        var policy = SearchPlaceholderPolicy()
        XCTAssertTrue(policy.isVisible)
        XCTAssertEqual(policy.hide(.signal), .signal)
        XCTAssertFalse(policy.isVisible)
        XCTAssertNil(policy.hide(.timeout), "a second hide must not re-log or change the reason")
        XCTAssertEqual(policy.hiddenReason, .signal)
    }

    func testRearmShowsAgainForTheNextVisit() {
        var policy = SearchPlaceholderPolicy()
        _ = policy.hide(.timeout)
        policy.rearm()
        XCTAssertTrue(policy.isVisible)
        XCTAssertEqual(policy.hide(.signal), .signal)
    }

    func testTimeoutOutlastsTheMeasuredFieldMountButIsBounded() {
        XCTAssertGreaterThan(SearchPlaceholderPolicy.timeout, 1.13)
        XCTAssertLessThanOrEqual(SearchPlaceholderPolicy.timeout, 2.0)
    }
}
