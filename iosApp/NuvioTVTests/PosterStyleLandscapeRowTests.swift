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

    // MARK: - BUG-162: card sizes for the three kinds of row

    /// Medium+ (134 dp), the size Steven runs: width 134 × 220/126, height × 1.5.
    private func mediumPlus() -> PosterStyle {
        var style = PosterStyle()
        style.width = 134 * (Theme.Size.posterWidth / 126)
        style.height = style.width * 1.5
        return style
    }

    func testPortraitCardIsThePoster() {
        let style = mediumPlus()
        XCTAssertEqual(style.cardWidth, style.width)
        XCTAssertEqual(style.cardHeight, style.height)
        XCTAssertFalse(style.landscapeRowGeometry)
    }

    func testGlobalLandscapeKeepsTheFixedCard() {
        var style = mediumPlus()
        style.landscapeCatalogRows = true
        XCTAssertEqual(style.cardWidth, Theme.Size.landscapeWidth)
        XCTAssertEqual(style.cardHeight, Theme.Size.landscapeHeight)
        XCTAssertTrue(style.landscapeRowGeometry, "the global toggle's rows are the short 203 pt rows")
    }

    func testShapeLandscapeIsTheTileAtThePosterHeight() {
        let base = mediumPlus()
        let style = base.resolved(forSectionItems: (0..<4).map { item("s\($0)", .landscape) })
        XCTAssertTrue(style.landscapeFromShape)
        XCTAssertEqual(style.cardHeight, base.height, "as tall as the portrait row")
        XCTAssertEqual(style.cardWidth, base.height * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(style.cardWidth, InlineTrailerCard.expandedWidth(style), accuracy: 0.001,
                       "the trailer tile's own width: a pure dissolve, no morph")
        XCTAssertFalse(style.landscapeRowGeometry, "planned as a portrait-height row")
        XCTAssertGreaterThan(style.cardHeight, Theme.Size.landscapeHeight)
    }

    func testShapeLandscapeFollowsPosterSize() {
        let items = (0..<3).map { item("p\($0)", .landscape) }
        let small = PosterStyle().withHeight(300).resolved(forSectionItems: items)
        let large = PosterStyle().withHeight(400).resolved(forSectionItems: items)
        XCTAssertEqual(small.cardHeight, 300)
        XCTAssertEqual(large.cardHeight, 400)
        XCTAssertLessThan(small.cardWidth, large.cardWidth)
    }

    func testGlobalToggleNeverTurnsIntoAShapeRow() {
        var style = mediumPlus()
        style.landscapeCatalogRows = true
        let resolved = style.resolved(forSectionItems: (0..<3).map { item("g\($0)", .landscape) })
        XCTAssertFalse(resolved.landscapeFromShape, "the global toggle wins, 360×203")
        XCTAssertEqual(resolved.cardWidth, Theme.Size.landscapeWidth)
    }

    func testStripInputsPlanAShapeRowAtThePortraitHeight() {
        let base = mediumPlus()
        let shape = base.resolved(forSectionItems: (0..<3).map { item("t\($0)", .landscape) })
        let portraitInputs = StripGeometry.Inputs.live(style: base, noZoom: true, leadingInset: 0)
        let shapeInputs = StripGeometry.Inputs.live(style: shape, noZoom: true, leadingInset: 0)
        XCTAssertEqual(shapeInputs, portraitInputs)
        var global = base
        global.landscapeCatalogRows = true
        XCTAssertTrue(StripGeometry.Inputs.live(style: global, noZoom: true, leadingInset: 0).landscapeCatalogRows)
    }
}
