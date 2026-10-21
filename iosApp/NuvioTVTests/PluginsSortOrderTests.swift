import XCTest
@testable import NuvioTV

final class PluginsSettingsRulesTests: XCTestCase {
    private struct Item { let name: String; let tag: Int }

    private func order(_ items: [Item]) -> [String] {
        PluginsViewModel.sortedByName(items, name: \.name).map(\.name)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(order([Item(name: "beta", tag: 0), Item(name: "Alpha", tag: 1), Item(name: "charlie", tag: 2)]),
                       ["Alpha", "beta", "charlie"])
    }

    func testNaturalNumberOrder() {
        XCTAssertEqual(order([Item(name: "Provider 10", tag: 0), Item(name: "Provider 2", tag: 1), Item(name: "Provider 1", tag: 2)]),
                       ["Provider 1", "Provider 2", "Provider 10"])
    }

    func testStableForEqualNames() {
        // Identical names keep their incoming order. ("same" vs "Same" is NOT a tie for
        // `localizedStandardCompare`: like the Finder, it puts the lowercase spelling first.)
        let sorted = PluginsViewModel.sortedByName(
            [Item(name: "Same", tag: 0), Item(name: "Aaa", tag: 1), Item(name: "Same", tag: 2), Item(name: "Same", tag: 3)],
            name: \.name
        )
        XCTAssertEqual(sorted.map(\.tag), [1, 0, 2, 3])
    }

    // Expansion rule (review r1 P2-1)
    func testLoneRepositoryDefaultsOpen() {
        XCTAssertTrue(PluginsViewModel.isRepositoryExpanded(stored: nil, repositoryCount: 1))
        XCTAssertFalse(PluginsViewModel.isRepositoryExpanded(stored: nil, repositoryCount: 2))
    }

    func testCollapsedLoneRepositoryStaysCollapsedWhenASecondIsInstalled() {
        XCTAssertFalse(PluginsViewModel.isRepositoryExpanded(stored: false, repositoryCount: 1))
        XCTAssertFalse(PluginsViewModel.isRepositoryExpanded(stored: false, repositoryCount: 2))
    }

    func testExpandedRepositoryStaysExpandedWhenAnotherIsRemoved() {
        XCTAssertTrue(PluginsViewModel.isRepositoryExpanded(stored: true, repositoryCount: 2))
        XCTAssertTrue(PluginsViewModel.isRepositoryExpanded(stored: true, repositoryCount: 1))
    }

    func testCaseDiffersLowercaseFirstLikeTheFinder() {
        XCTAssertEqual(order([Item(name: "Same", tag: 0), Item(name: "same", tag: 1)]), ["same", "Same"])
    }
}
