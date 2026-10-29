import XCTest
import SharedCore
@testable import NuvioTV

/// BUG-189: Discover's standard genre and catalog names are localized for display only; unknown
/// names pass through, matching is trimmed and case-insensitive, and selection / fetch keys and
/// the catalog-clash check keep the raw manifest names. Expected values go through
/// `String(localized:)` too, so the tests hold under any test-runner language.
@MainActor
final class DiscoverGenreNamesTests: XCTestCase {

    private func option(_ key: String,
                        name: String = "Popular",
                        addon: String = "Cinemeta",
                        genres: [String] = [],
                        genreRequired: Bool = false) -> DiscoverCatalogOption {
        DiscoverCatalogOption(key: key,
                              addonName: addon,
                              manifestUrl: "https://\(addon.lowercased()).example/manifest.json",
                              type: "movie",
                              catalogId: "cat-\(key)",
                              catalogName: name,
                              genreOptions: genres,
                              genreRequired: genreRequired,
                              supportsPagination: true)
    }

    // MARK: - Mapping

    func testCinemetaGenresMap() {
        XCTAssertEqual(DiscoverGenreNames.display("Action"), String(localized: "Action", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("Sci-Fi"), String(localized: "Sci-Fi", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("Reality-TV"), String(localized: "Reality-TV", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("Film-Noir"), String(localized: "Film-Noir", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("Short"), String(localized: "Short", comment: "Discover genre"))
    }

    func testTmdbGenresMap() {
        XCTAssertEqual(DiscoverGenreNames.display("Science Fiction"),
                       String(localized: "Science Fiction", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("Action & Adventure"),
                       String(localized: "Action & Adventure", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("TV Movie"), String(localized: "TV Movie", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.display("Soap"), String(localized: "Soap", comment: "Discover genre"))
    }

    func testCatalogNamesMap() {
        XCTAssertEqual(DiscoverGenreNames.catalogDisplay("Popular"), String(localized: "Popular", comment: "Discover catalog"))
        XCTAssertEqual(DiscoverGenreNames.catalogDisplay("Top Rated"), String(localized: "Top Rated", comment: "Discover catalog"))
        XCTAssertEqual(DiscoverGenreNames.catalogDisplay("New"), String(localized: "New", comment: "Discover catalog"))
    }

    func testCaseAndWhitespaceAreIgnored() {
        let action = String(localized: "Action", comment: "Discover genre")
        XCTAssertEqual(DiscoverGenreNames.display("action"), action)
        XCTAssertEqual(DiscoverGenreNames.display("  ACTION \n"), action)
        XCTAssertEqual(DiscoverGenreNames.display("sci-fi & FANTASY"),
                       String(localized: "Sci-Fi & Fantasy", comment: "Discover genre"))
        XCTAssertEqual(DiscoverGenreNames.catalogDisplay(" top rated "),
                       String(localized: "Top Rated", comment: "Discover catalog"))
    }

    func testUnknownNamesPassThroughUntouched() {
        XCTAssertEqual(DiscoverGenreNames.display("Isekai"), "Isekai")
        XCTAssertEqual(DiscoverGenreNames.display(" Isekai "), " Isekai ", "pass-through keeps the raw value")
        XCTAssertEqual(DiscoverGenreNames.display("Action-Comedy"), "Action-Comedy")
        XCTAssertEqual(DiscoverGenreNames.catalogDisplay("Netflix Originals"), "Netflix Originals")
        // A genre name is not a catalog name and vice versa.
        XCTAssertEqual(DiscoverGenreNames.catalogDisplay("Action"), "Action")
        XCTAssertEqual(DiscoverGenreNames.display("Popular"), "Popular")
    }

    // MARK: - List labels (review r1)

    /// Two raw names with one localized label: the first takes the label, the later one its raw name.
    func testDisplayLabelsShowRawForADuplicateLabel() {
        let french: (String) -> String = { raw in
            ["sci-fi": "Science-fiction", "science fiction": "Science-fiction",
             "action": "Action"][DiscoverGenreNames.normalized(raw)] ?? raw
        }
        XCTAssertEqual(DiscoverGenreNames.displayLabels(["Action", "Sci-Fi", "Science Fiction"], display: french),
                       ["Action", "Science-fiction", "Science Fiction"])
        XCTAssertEqual(DiscoverGenreNames.displayLabels(["Science Fiction", "Sci-Fi"], display: french),
                       ["Science-fiction", "Sci-Fi"], "whichever raw comes first takes the label")
    }

    /// Distinct labels are untouched, and the real mapping collapses case variants the same way.
    func testDisplayLabelsRealMapping() {
        let action = String(localized: "Action", comment: "Discover genre")
        XCTAssertEqual(DiscoverGenreNames.displayLabels(["Action", "Isekai"]), [action, "Isekai"])
        XCTAssertEqual(DiscoverGenreNames.displayLabels(["Action", "action"]), [action, "action"])
        XCTAssertEqual(DiscoverGenreNames.displayLabels([]), [])
    }

    func testGenrePillLabelsDeduplicateAndKeepAll() {
        let action = String(localized: "Action", comment: "Discover genre")
        let labels = DiscoverGridPlan.genreLabels([DiscoverGridPlan.allGenre, "Action", "action"])
        XCTAssertEqual(labels[DiscoverGridPlan.allGenre], String(localized: "All"))
        XCTAssertEqual(labels["Action"], action)
        XCTAssertEqual(labels["action"], "action")
    }

    func testGenreRowsDeduplicateHeadingsButFetchRawGenre() {
        let action = String(localized: "Action", comment: "Discover genre")
        let movies = option("m", genres: ["Action", "action"])
        let specs = DiscoverRowsPlan.specs(for: movies, catalogs: [movies])
        XCTAssertEqual(specs.map(\.title), [action, "action"])
        XCTAssertEqual(specs.map(\.genre), ["Action", "action"])
    }

    // MARK: - Call sites

    func testGenreLabelLocalizesButAllStaysAll() {
        XCTAssertEqual(DiscoverGridPlan.genreLabel(DiscoverGridPlan.allGenre), String(localized: "All"))
        XCTAssertEqual(DiscoverGridPlan.genreLabel("comedy"), String(localized: "Comedy", comment: "Discover genre"))
        // The pill value itself stays raw.
        XCTAssertEqual(DiscoverGridPlan.genre(fromPill: "comedy"), "comedy")
    }

    func testGenreRowsLocalizeTitleButFetchRawGenre() {
        let movies = option("m", genres: ["action", "Isekai"])
        let specs = DiscoverRowsPlan.specs(for: movies, catalogs: [movies])
        XCTAssertEqual(specs.map(\.title), [String(localized: "Action", comment: "Discover genre"), "Isekai"])
        XCTAssertEqual(specs.map(\.genre), ["action", "Isekai"], "the fetch keeps the manifest genre")
        XCTAssertEqual(specs.map(\.key), ["discover|m|g0", "discover|m|g1"], "keys never carry the label")
    }

    func testFallbackRowsLocalizeCatalogTitles() {
        let a = option("a", name: "top rated")
        let b = option("b", name: "My List")
        let specs = DiscoverRowsPlan.fallbackSpecs(selected: a, catalogs: [a, b])
        XCTAssertEqual(specs.map(\.title), [String(localized: "Top Rated", comment: "Discover catalog"), "My List"])
    }

    func testCatalogClashComparesRawNames() {
        let popular = String(localized: "Popular", comment: "Discover catalog")
        let a = option("a", name: "Popular", addon: "Cinemeta")
        let b = option("b", name: " popular", addon: "TMDB")   // localizes the same, raw differs
        let c = option("c", name: "popular", addon: "Trakt")
        // a and c clash on the raw name (case-insensitive); b's raw name has a leading space, so
        // it does not clash with either even though all three display as "Popular".
        XCTAssertEqual(DiscoverRowsPlan.catalogLabel(a, among: [a, b, c]), "\(popular) \u{00B7} Cinemeta")
        XCTAssertEqual(DiscoverRowsPlan.catalogLabel(c, among: [a, b, c]), "\(popular) \u{00B7} Trakt")
        XCTAssertEqual(DiscoverRowsPlan.catalogLabel(b, among: [a, b, c]), popular)
    }
}
