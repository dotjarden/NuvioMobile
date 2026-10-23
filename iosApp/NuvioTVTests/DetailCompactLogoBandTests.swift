import XCTest
@testable import NuvioTV

/// D-3 (design review 2026-10-22): the band-crossing rule behind the compact logo's fade on the
/// scrolled Cinematic Detail page. Rows are given in content coordinates, the way
/// `DetailRowAnchored` reports them; a row's screen top is `top − contentOffset`.
final class DetailCompactLogoBandTests: XCTestCase {
    private typealias Band = DetailCompactLogoBand
    private typealias Row = DetailCompactLogoBand.Row

    /// The Parental Guide row (title + gap + one chip line).
    private let parentalHeight: CGFloat = 100
    /// A cast shelf (title, avatars, two caption lines).
    private let castHeight: CGFloat = 250

    func testBandIsTheLogoSlot() {
        XCTAssertEqual(Band.bandTop, 36)
        XCTAssertEqual(Band.bandBottom, 108)
        XCTAssertEqual(Band.bandBottom, DetailRowAnchor.screenRest,
                       "an anchored row's top rests exactly at the band's bottom")
    }

    /// The review shots: the Parental Guide heading at ~40 pt and its chips under the logo.
    func testParentalGuideRestingInTheBandBlocks() {
        let rows = [Row(top: 2000, height: parentalHeight)]
        XCTAssertTrue(Band.blocked(rows: rows, contentOffset: 2000 - 40))
    }

    /// Heading scrolled off, chips still in the band (an Up anchor onto the row below): blocked.
    func testChipsAloneInTheBandBlock() {
        // Row below rests at 108, so this row's bottom is at 108 − 36 = 72 and its top at −28.
        let rows = [Row(top: 1000, height: parentalHeight)]
        XCTAssertTrue(Band.blocked(rows: rows, contentOffset: 1000 + 28))
    }

    /// A shelf's tail above an anchored row is under the scrim, not a heading: the logo shows.
    func testShelfTailAboveAnAnchoredRowIsClear() {
        // Cast above a row anchored at 108: bottom at 72, top at 72 − 250 = −178.
        let cast = Row(top: 1000, height: castHeight)
        let next = Row(top: 1000 + castHeight + 36, height: 300)
        let offset: CGFloat = 1000 + 178
        XCTAssertEqual(next.top - offset, DetailRowAnchor.screenRest)
        XCTAssertFalse(Band.blocked(rows: [cast, next], contentOffset: offset))
    }

    /// A shelf heading passing through the band blocks; its lead is capped at `leadDepth`.
    func testShelfHeadingInTheBandBlocksUntilItsLeadClears() {
        let cast = Row(top: 1000, height: castHeight)
        XCTAssertTrue(Band.blocked(rows: [cast], contentOffset: 1000 - 60), "heading at 60")
        // Lead bottom at screenTop + 112: clear once it is at or above the band's top (36).
        XCTAssertTrue(Band.blocked(rows: [cast], contentOffset: 1000 + 75), "lead bottom at 37")
        XCTAssertFalse(Band.blocked(rows: [cast], contentOffset: 1000 + 76), "lead bottom at 36")
    }

    /// Edges touching the band do not count; the bottom edge has `restTolerance` (16 pt).
    func testEdgesTouchingTheBandAreClear() {
        let row = Row(top: 500, height: parentalHeight)
        XCTAssertFalse(Band.blocked(rows: [row], contentOffset: 500 - 108), "top exactly at the band's bottom")
        XCTAssertFalse(Band.blocked(rows: [row], contentOffset: 500 + parentalHeight - 36), "bottom exactly at the band's top")
        XCTAssertTrue(Band.blocked(rows: [row], contentOffset: 500 + parentalHeight - 37))
    }

    /// Review P2-2: an anchored row resting a fraction or a few points above `screenRest` must not
    /// hide the logo with its own heading; past the tolerance its heading is inside the slot.
    func testRestToleranceAtTheBandBottom() {
        XCTAssertEqual(Band.restTolerance, 16)
        let row = Row(top: 500, height: castHeight)
        XCTAssertFalse(Band.blocked(rows: [row], contentOffset: 500 - 107.5), "fractional rest at 107.5")
        XCTAssertFalse(Band.blocked(rows: [row], contentOffset: 500 - 92), "rest 16 pt high (92)")
        XCTAssertTrue(Band.blocked(rows: [row], contentOffset: 500 - 91.5), "heading at 91.5 is inside the slot")
    }

    /// A row whose lead ends exactly at the band's top is clear, half a point lower blocks; a row
    /// exactly `leadDepth` tall behaves the same as a taller one.
    func testLeadExactlyAtLeadDepth() {
        for height in [Band.leadDepth, castHeight] {
            let row = Row(top: 1000, height: height)
            // Lead bottom = screenTop + 112: at 36 when screenTop = −76.
            XCTAssertFalse(Band.blocked(rows: [row], contentOffset: 1000 + 76), "height \(height): lead bottom at 36")
            XCTAssertTrue(Band.blocked(rows: [row], contentOffset: 1000 + 75.5), "height \(height): lead bottom at 36.5")
        }
    }

    /// Rows wholly below the band (the next row revealed lower down) or above it are clear.
    func testRowsOutsideTheBandAreClear() {
        let rows = [Row(top: 400, height: parentalHeight), Row(top: 2000, height: castHeight)]
        // Offset 600: first row spans −200…−100, second sits at 1400.
        XCTAssertFalse(Band.blocked(rows: rows, contentOffset: 600))
        XCTAssertFalse(Band.blocked(rows: [], contentOffset: 600))
    }

    /// An unmeasured (zero-height) row never blocks.
    func testZeroHeightRowIsIgnored() {
        XCTAssertFalse(Band.blocked(rows: [Row(top: 1000, height: 0)], contentOffset: 1000 - 60))
    }

    /// The band is only evaluated once the hero has gone (`heroClearance` keeps its meaning).
    func testGateIgnoresTheBandInsideTheHero() {
        let rows = [Row(top: 1000, height: parentalHeight)]
        let inHero = Band.gate(heroGone: false, rows: rows, contentOffset: 1000 - 60)
        XCTAssertEqual(inHero, .init(heroGone: false, bandBlocked: false))
        let past = Band.gate(heroGone: true, rows: rows, contentOffset: 1000 - 60)
        XCTAssertEqual(past, .init(heroGone: true, bandBlocked: true))
    }

    func testShowsTruthTable() {
        XCTAssertTrue(Band.shows(inRows: true, gate: .init(heroGone: true, bandBlocked: false)))
        XCTAssertFalse(Band.shows(inRows: true, gate: .init(heroGone: true, bandBlocked: true)))
        XCTAssertFalse(Band.shows(inRows: true, gate: .init(heroGone: false, bandBlocked: false)))
        XCTAssertFalse(Band.shows(inRows: false, gate: .init(heroGone: true, bandBlocked: false)))
    }
}
