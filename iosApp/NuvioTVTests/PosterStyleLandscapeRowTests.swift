import XCTest
import SharedCore
@testable import NuvioTV

/// BUG-157 (Steven, beta.19-rc3 follow-up 2026-10-14): an add-on catalog whose items carry
/// `posterShape: "landscape"` draws one landscape row. The pure rule is a strict majority of the
/// row's items; `resolved(forSectionItems:)` ORs it with the global Landscape Posters toggle.
@MainActor
final class PosterStyleLandscapeRowTests: XCTestCase {

    func testEmptyRowStaysPortrait() {
        XCTAssertFalse(PosterStyle.landscapeSection([Bool]()))
    }

    func testAllLandscapeIsLandscape() {
        XCTAssertTrue(PosterStyle.landscapeSection([true]))
        XCTAssertTrue(PosterStyle.landscapeSection([true, true, true]))
    }

    func testStrictMajorityDecides() {
        XCTAssertTrue(PosterStyle.landscapeSection([true, true, false]), "2 of 3")
        XCTAssertFalse(PosterStyle.landscapeSection([true, false]), "a tie stays portrait")
        XCTAssertFalse(PosterStyle.landscapeSection([true, false, false]), "1 of 3")
        XCTAssertFalse(PosterStyle.landscapeSection([false, false, false]))
    }

    func testOneStrayTagNeverFlipsARow() {
        var flags = Array(repeating: false, count: 18)
        flags[0] = true
        XCTAssertFalse(PosterStyle.landscapeSection(flags), "a stray first item does not decide the row")
        flags = Array(repeating: true, count: 18)
        flags[0] = false
        XCTAssertTrue(PosterStyle.landscapeSection(flags), "nor does a stray portrait one")
    }

    func testEmptyItemsResolveToTheInheritedStyle() {
        var style = PosterStyle()
        XCTAssertEqual(style.resolved(forSectionItems: []), style)
        style.landscapeCatalogRows = true
        XCTAssertEqual(style.resolved(forSectionItems: []), style, "the global toggle still forces landscape")
    }

    // MARK: - Over real items (`MetaPreview.posterShape`)

    private func item(_ id: String, _ shape: PosterShape) -> MetaPreview {
        MetaPreview(
            id: id, type: "movie", name: "Title \(id)",
            poster: nil, banner: nil, logo: nil,
            posterShape: shape,
            description: nil, releaseInfo: nil, rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: nil,
            genres: [],
            rawPosterUrl: nil,
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: false
        )
    }

    func testLandscapeCatalogTurnsTheRowLandscape() {
        let items = (0..<5).map { item("l\($0)", .landscape) }
        XCTAssertTrue(PosterStyle.landscapeSection(items: items))
        let resolved = PosterStyle().resolved(forSectionItems: items)
        XCTAssertTrue(resolved.landscapeCatalogRows)
        // Only the shape flag changes: the poster size, corners and captions stay the user's.
        XCTAssertEqual(resolved.width, PosterStyle().width)
        XCTAssertEqual(resolved.height, PosterStyle().height)
        XCTAssertEqual(resolved.showTitle, PosterStyle().showTitle)
    }

    func testSquareAndPosterStayPortrait() {
        let items = [item("a", .square), item("b", .square), item("c", .poster)]
        XCTAssertFalse(PosterStyle.landscapeSection(items: items))
        XCTAssertEqual(PosterStyle().resolved(forSectionItems: items), PosterStyle())
    }

    func testGlobalToggleStillWinsOnAPortraitRow() {
        var style = PosterStyle()
        style.landscapeCatalogRows = true
        let items = [item("a", .poster), item("b", .poster)]
        XCTAssertTrue(style.resolved(forSectionItems: items).landscapeCatalogRows)
    }
}
