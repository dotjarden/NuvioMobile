import XCTest
@testable import NuvioTV

/// UX-19: the hero's text stand-in is never a content id.
final class HeroTitleTextTests: XCTestCase {
    func testIdShapesAreIdentifiers() {
        for id in ["tt3118958", "tt0111161", "tt30459041:1:7", "tmdb:12345", "tmdb:12345:2:3", "trakt:99", "kitsu:1",
                   "mal:20", "anilist:5", "anidb:7", "simkl:77", "tvdb:8", "imdb:tt123", "  tt3118958  ", "TT3118958"] {
            XCTAssertTrue(HeroTitleText.isIdentifier(id), id)
        }
    }

    func testTitlesAreNot() {
        for name in ["Lizzie Borden Took an Ax", "Animals", "2001: A Space Odyssey", "1917", "300", "2012", "24", "一一",
                     "tt", "Tenet", "Se7en", "tmdb: the movie", "tt123: Part Two", "", "   "] {
            XCTAssertFalse(HeroTitleText.isIdentifier(name), name)
        }
    }

    /// The name equal to the item's own id (the shared fallbacks `title ?: parentMetaId`) is an id
    /// whatever its shape, including a `:season:episode` head.
    func testNameEqualToTheItemsIdIsAnIdentifier() {
        XCTAssertTrue(HeroTitleText.isIdentifier("abc-custom-9", id: "abc-custom-9"))
        XCTAssertTrue(HeroTitleText.isIdentifier("tt1:1:7", id: "tt1"))
        XCTAssertTrue(HeroTitleText.isIdentifier("tt1", id: "tt1:1:7"))
        XCTAssertFalse(HeroTitleText.isIdentifier("1917", id: "tt0000001"))
        XCTAssertFalse(HeroTitleText.isIdentifier("Lost: Season 1", id: "lost"))
        XCTAssertFalse(HeroTitleText.isIdentifier("Animals", id: "tt3118958"))
    }
}
