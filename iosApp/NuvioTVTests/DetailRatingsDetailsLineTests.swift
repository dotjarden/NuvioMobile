import XCTest
@testable import NuvioTV

/// D-5 (design review 2026-10-22): Classic's Details block prints the ratings with Cinematic's
/// brand labels and order, on one wrappable line.
final class DetailRatingsDetailsLineTests: XCTestCase {
    func testBrandLabelsAndCinematicOrder() {
        let line = DetailRatings.detailsLine(DetailRatings.ordered([
            DetailRatingInput(source: "letterboxd", value: 2.2),
            DetailRatingInput(source: "tomatoes", value: 91),
            DetailRatingInput(source: "imdb", value: 8.14),
        ]))
        XCTAssertEqual(line, "IMDb 8.1  \u{00B7}  Rotten Tomatoes 91%  \u{00B7}  Letterboxd 2.2")
        XCTAssertFalse(line.contains("imdb"), "the add-on's raw key must not reach the page")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(DetailRatings.detailsLine([]), "")
    }
}
