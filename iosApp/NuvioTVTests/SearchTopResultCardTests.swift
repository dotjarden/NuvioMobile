import XCTest
import SharedCore
@testable import NuvioTV

/// B8 (FEAT-72; Steven, beta.19-rc4 verdict 2026-10-16: "title, year, type only"): the Best Result
/// card's meta line is always the type, then the year when there is one; never a rating.
@MainActor
final class SearchTopResultCardTests: XCTestCase {

    private func item(type: String, year: String?, rating: String? = "8.0") -> MetaPreview {
        MetaPreview(
            id: "tt1", type: type, name: "Title",
            poster: nil, banner: nil, logo: nil,
            posterShape: .poster,
            description: nil, releaseInfo: year, rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: rating,
            genres: [],
            rawPosterUrl: nil,
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: false
        )
    }

    func testMovieShowsTypeAndYearWithoutRating() {
        XCTAssertEqual(SearchTopResultCard.metaLine(item(type: "movie", year: "2009")),
                       "\(String(localized: "Movie")) \u{00B7} 2009")
    }

    func testSeriesShowsTypeAndYear() {
        XCTAssertEqual(SearchTopResultCard.metaLine(item(type: "series", year: "2021")),
                       "\(String(localized: "Series")) \u{00B7} 2021")
    }

    func testMissingYearShowsTheTypeAlone() {
        XCTAssertEqual(SearchTopResultCard.metaLine(item(type: "movie", year: nil)), String(localized: "Movie"))
        XCTAssertEqual(SearchTopResultCard.metaLine(item(type: "series", year: "  ")), String(localized: "Series"))
    }

    func testUnknownTypeIsCapitalizedAndBlankTypeIsDropped() {
        XCTAssertEqual(SearchTopResultCard.metaLine(item(type: "channel", year: "2020")), "Channel \u{00B7} 2020")
        XCTAssertEqual(SearchTopResultCard.metaLine(item(type: " ", year: "2020")), "2020")
        XCTAssertNil(SearchTopResultCard.metaLine(item(type: "", year: nil)))
    }
}
