import XCTest
@testable import NuvioTV

/// UX-19: the hero's text stand-in is never a content id.
final class HeroTitleTextTests: XCTestCase {
    func testIdsAreIdentifiers() {
        for id in ["tt3118958", "tt0111161", "tt30459041:1:7", "tmdb:12345", "trakt:99", "kitsu:1", "mal:20",
                   "anilist:5", "simkl:77", "12345", "  tt3118958  ", "TT3118958"] {
            XCTAssertTrue(HeroTitleText.isIdentifier(id), id)
        }
    }

    func testTitlesAreNot() {
        for name in ["Lizzie Borden Took an Ax", "Animals", "2001: A Space Odyssey", "1917", "tt", "Tenet",
                     "Se7en", "tmdb: the movie", "", "   "] {
            if name == "1917" { continue }   // a bare number IS treated as an id; the title "1917" is the known cost
            XCTAssertFalse(HeroTitleText.isIdentifier(name), name)
        }
    }

    func testBareNumberIsTheKnownCost() {
        // Documented trade: a film called "1917" shows no text wordmark when it has no logo (it has one
        // on every catalog that matters); an id printed as a title is the worse failure.
        XCTAssertTrue(HeroTitleText.isIdentifier("1917"))
    }
}
