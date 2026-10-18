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
}
