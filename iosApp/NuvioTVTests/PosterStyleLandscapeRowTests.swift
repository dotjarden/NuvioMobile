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

    /// BUG-162 / D16 (Steven, rc5 verdict 2026-10-17): a shape-landscape card RESTS at the landscape
    /// folder tile's size (`FolderTile`: `width × 16/9` × `width`, 416×234 at Medium+) and GROWS to
    /// the trailer tile at the poster height (624×351) at the `.wide` stage.
    func testShapeLandscapeRestsAtTheFolderTileSize() {
        let base = mediumPlus()
        let style = base.resolved(forSectionItems: (0..<4).map { item("s\($0)", .landscape) })
        XCTAssertTrue(style.landscapeFromShape)
        XCTAssertEqual(style.cardWidth, base.width * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(style.cardHeight, base.width, accuracy: 0.001, "the folder tile's height")
        XCTAssertEqual(style.cardWidth, 416, accuracy: 0.5, "416 × 234 at Medium+")
        XCTAssertEqual(style.cardHeight, 234, accuracy: 0.5)
        XCTAssertFalse(style.landscapeRowGeometry, "planned as a portrait-height row")
    }

    /// The SLOT (Classic's planners): the tile at the poster height. Since Steven's rc6 19:47Z note the
    /// card itself no longer grows into it (`testShapeLandscapeTrailerPlaysAtTheRestingSize`).
    func testShapeLandscapeGrowsToTheTileAtThePosterHeight() {
        let base = mediumPlus()
        let style = base.resolved(forSectionItems: (0..<4).map { item("s\($0)", .landscape) })
        XCTAssertEqual(style.expandedCardHeight, base.height, "grows to the portrait row's height")
        XCTAssertEqual(style.expandedCardWidth, base.height * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(style.expandedCardWidth, InlineTrailerCard.expandedWidth(style), accuracy: 0.001,
                       "the same tile a portrait card grows to")
        XCTAssertEqual(style.expandedCardWidth, 624, accuracy: 0.5)
        XCTAssertEqual(style.expandedCardHeight, 351, accuracy: 0.5)
        XCTAssertGreaterThan(style.expandedCardHeight, style.cardHeight)
    }

    func testShapeLandscapeFollowsPosterSize() {
        let items = (0..<3).map { item("p\($0)", .landscape) }
        for dp in [105.0, 126.0, 134.0, 154.0] {
            var base = PosterStyle()
            base.width = CGFloat(dp) * (Theme.Size.posterWidth / 126)
            base.height = base.width * 1.5
            let style = base.resolved(forSectionItems: items)
            XCTAssertEqual(style.cardWidth, base.width * 16 / 9, accuracy: 0.001, "rest width at \(dp) dp")
            XCTAssertEqual(style.cardHeight, base.width, accuracy: 0.001, "rest height at \(dp) dp")
            XCTAssertEqual(style.expandedCardWidth, base.height * 16 / 9, accuracy: 0.001, "grown width at \(dp) dp")
            XCTAssertEqual(style.expandedCardHeight, base.height, accuracy: 0.001, "grown height at \(dp) dp")
        }
        let small = PosterStyle().withHeight(300).resolved(forSectionItems: items)
        let large = PosterStyle().withHeight(400).resolved(forSectionItems: items)
        XCTAssertEqual(small.expandedCardHeight, 300)
        XCTAssertEqual(large.expandedCardHeight, 400)
        XCTAssertLessThan(small.cardWidth, large.cardWidth)
    }

    /// The stage → artwork-size table `InlineTrailerCard.artworkWidth/Height` read
    /// (`PosterStyle.artworkSize(expanded:)`; `expanded` = `.wide`, `.reveal` dissolves at rest).
    func testArtworkSizeByStageForTheThreeRowKinds() {
        let portrait = mediumPlus()
        XCTAssertEqual(portrait.artworkSize(expanded: false), CGSize(width: portrait.width, height: portrait.height))
        XCTAssertEqual(portrait.artworkSize(expanded: true).width, portrait.height * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(portrait.artworkSize(expanded: true).height, portrait.height, "UX-4a: height never changes")

        let shape = portrait.resolved(forSectionItems: (0..<3).map { item("a\($0)", .landscape) })
        XCTAssertEqual(shape.artworkSize(expanded: false), CGSize(width: shape.cardWidth, height: shape.cardHeight))
        // Steven rc6 19:47Z: the shape card plays its trailer at the resting size.
        XCTAssertEqual(shape.artworkSize(expanded: true), CGSize(width: shape.cardWidth, height: shape.cardHeight))

        var global = portrait
        global.landscapeCatalogRows = true
        let landscapeCard = CGSize(width: Theme.Size.landscapeWidth, height: Theme.Size.landscapeHeight)
        XCTAssertEqual(global.artworkSize(expanded: false), landscapeCard)
        XCTAssertEqual(global.artworkSize(expanded: true), landscapeCard, "the global toggle's tile never grows")
        XCTAssertEqual(global.expandedCardWidth, global.cardWidth)
        XCTAssertEqual(global.expandedCardHeight, global.cardHeight)
    }

    /// The morph scroll (M3) gets the card's own rest → `.wide` widths. A shape row's card 3 at
    /// Medium+ (leading 3 × (416 + 28) = 1332, grown trailing 1956) overflows a 1920 row and
    /// scrolls; the old portrait widths (234 → 624, leading 786) called it a fit.
    func testMorphScrollPlansAShapeLandscapeGrow() {
        let shape = mediumPlus().resolved(forSectionItems: (0..<10).map { item("m\($0)", .landscape) })
        let gap = Theme.Spacing.rowGap
        let count: CGFloat = 10
        let content = count * shape.cardWidth + (count - 1) * gap
        let plan = RowMorphScroll.plan(index: 3, restingWidth: shape.cardWidth,
                                       expandedWidth: shape.expandedCardWidth, gap: gap,
                                       visibleMinX: 0, viewportWidth: 1920, contentWidth: content,
                                       insetLeading: 0, contentAlreadyGrown: false)
        let trailing = 3 * (shape.cardWidth + gap) + shape.expandedCardWidth
        XCTAssertEqual(plan.offset ?? -1, trailing - 1920, accuracy: 0.001)
        XCTAssertTrue(plan.overflowsViewport)
        let old = RowMorphScroll.plan(index: 3, restingWidth: shape.width,
                                      expandedWidth: InlineTrailerCard.expandedWidth(shape), gap: gap,
                                      visibleMinX: 0, viewportWidth: 1920, contentWidth: content,
                                      insetLeading: 0, contentAlreadyGrown: false)
        XCTAssertNil(old.offset, "the pre-D16 widths missed the overflow")

        var global = mediumPlus()
        global.landscapeCatalogRows = true
        XCTAssertNil(RowMorphScroll.plan(index: 9, restingWidth: global.cardWidth,
                                         expandedWidth: global.expandedCardWidth, gap: gap,
                                         visibleMinX: 0, viewportWidth: 1920, contentWidth: 4000,
                                         insetLeading: 0, contentAlreadyGrown: false).offset,
                     "the global toggle's card never grows: nothing to scroll for")
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

    // MARK: - Steven rc6 19:47Z: wide trailers at the resting size

    func testShapeLandscapeTrailerPlaysAtTheRestingSize() {
        let base = mediumPlus()
        let style = base.resolved(forSectionItems: (0..<4).map { item("s\($0)", .landscape) })
        XCTAssertEqual(style.artworkSize(expanded: true), style.artworkSize(expanded: false),
                       "a shape-landscape card plays its trailer at 416 × 234, it never grows")
        XCTAssertEqual(style.trailerCardWidth, style.cardWidth, accuracy: 0.001)
        XCTAssertEqual(style.trailerCardHeight, style.cardHeight, accuracy: 0.001)
    }

    func testPortraitStillMorphsToTheTile() {
        let style = mediumPlus()
        XCTAssertEqual(style.artworkSize(expanded: true).width, style.height * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(style.artworkSize(expanded: true).height, style.height, accuracy: 0.001)
    }
}
