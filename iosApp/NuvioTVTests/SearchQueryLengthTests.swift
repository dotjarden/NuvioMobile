import XCTest
@testable import NuvioTV

/// B18 (BUG-155 (d)): a single Latin letter does not search; a single non-ASCII character (one CJK
/// character can be a whole title) and anything longer do.
@MainActor
final class SearchQueryLengthTests: XCTestCase {

    func testSingleLatinLetterIsTooShort() {
        XCTAssertTrue(SearchViewModel.isTooShortToSearch("a"))
        XCTAssertTrue(SearchViewModel.isTooShortToSearch("7"))
    }

    func testTwoCharactersAndNonASCIISingletonsSearch() {
        XCTAssertFalse(SearchViewModel.isTooShortToSearch("du"))
        XCTAssertFalse(SearchViewModel.isTooShortToSearch("鬼"))
        XCTAssertFalse(SearchViewModel.isTooShortToSearch("é"))
    }

    func testDebounceIsLongerThanBefore() {
        XCTAssertEqual(SearchViewModel.debounceNanoseconds, 450_000_000)
    }

    /// H3 (BUG-208 investigation): a debounce `stop()` cancelled is re-armed on `start()` only when
    /// it still owes a search the active one does not cover.
    func testResumeQueryAfterTabSwitch() {
        XCTAssertEqual(SearchViewModel.queryToResume(pending: "Avatar", active: "Avat"), "Avatar")
        XCTAssertEqual(SearchViewModel.queryToResume(pending: "Avatar", active: nil), "Avatar")
        XCTAssertNil(SearchViewModel.queryToResume(pending: "Avatar", active: "Avatar"))
        XCTAssertNil(SearchViewModel.queryToResume(pending: nil, active: "Avat"))
        XCTAssertNil(SearchViewModel.queryToResume(pending: "", active: "Avat"))
    }
}
