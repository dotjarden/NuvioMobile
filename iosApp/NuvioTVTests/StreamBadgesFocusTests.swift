import XCTest
@testable import NuvioTV

/// Wave 3b review r1 P3-7: where focus goes after Delete Badge Pack (`StreamBadgesSection`).
final class StreamBadgesFocusTests: XCTestCase {
    func testDeleteHandsFocusToTheNextPack() {
        let urls = ["https://a/pack.json", "https://b/pack.json", "https://c/pack.json"]
        XCTAssertEqual(StreamBadgesSection.packFocusAfterDeleting(urls[0], in: urls), urls[1])
        XCTAssertEqual(StreamBadgesSection.packFocusAfterDeleting(urls[1], in: urls), urls[2])
    }

    /// The last pack (or the only one) has no pack below it: nil, and the section focuses the URL
    /// field instead.
    func testTheLastPackHandsFocusToTheUrlField() {
        let urls = ["https://a/pack.json", "https://b/pack.json"]
        XCTAssertNil(StreamBadgesSection.packFocusAfterDeleting(urls[1], in: urls))
        XCTAssertNil(StreamBadgesSection.packFocusAfterDeleting(urls[0], in: [urls[0]]))
        XCTAssertNil(StreamBadgesSection.packFocusAfterDeleting("https://gone/pack.json", in: urls))
    }
}
