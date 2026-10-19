import XCTest
import CoreGraphics
@testable import NuvioTV

/// FEAT-61 (Steven rc3) — Settings › Home Screen › Synopsis Length = Long, the line-budget math in
/// `PinnedRowGeometry.LongSynopsis`.
///
/// Pure arithmetic, like `PinnedRowGeometryTests`. The invariant that matters for BUG-87/89 is that
/// Long never needs more height than the hero frame already has: the rows' plan is computed without
/// this setting, so as long as the grown content fits the unchanged frame, nothing below the hero
/// can move. What these tests cannot prove is how the text looks on the TV — that is the device pass.
final class LongSynopsisTests: XCTestCase {

    private typealias Long = PinnedRowGeometry.LongSynopsis

    /// `Theme.Font.synopsisLineHeight`: system caption1 ≈30, Open Sans at the 0.92 scale ≈31.32.
    private static let systemLine: CGFloat = 30
    private static let openSansLine: CGFloat = 31.32
    private static let lineHeights: [CGFloat] = [systemLine, openSansLine]

    private static func posterHeight(dp: CGFloat) -> CGFloat {
        dp * (Theme.Size.posterWidth / 126.0) * 1.5
    }
    private static let sizes: [CGFloat] = [105, 126, 134, 154].map { posterHeight(dp: $0) }
    private static let large = posterHeight(dp: 154)

    private static func mode(noZoom: Bool) -> PinnedRowTitle.FocusModeFlags {
        // Both reach holds ON: their shipping defaults (`resolveReachHoldsLift` / `resolveZoomReachHold`).
        PinnedRowTitle.FocusModeFlags(noZoom: noZoom, accentRing: false,
                                      reachHoldsLift: true, zoomReachHold: true)
    }

    // MARK: - The setting

    func testSynopsisLengthDefaultsToStandard() {
        XCTAssertEqual(PinnedRowGeometry.SynopsisLength.defaultValue, .standard)
        XCTAssertEqual(PinnedRowGeometry.SynopsisLength.resolve(nil), .standard)
        XCTAssertEqual(PinnedRowGeometry.SynopsisLength.resolve(""), .standard)
        XCTAssertEqual(PinnedRowGeometry.SynopsisLength.resolve("bogus"), .standard)
        XCTAssertEqual(PinnedRowGeometry.SynopsisLength.resolve(" Long "), .long)
        XCTAssertEqual(PinnedRowGeometry.SynopsisLength.resolve("standard"), .standard)
    }

    // MARK: - The core rule

    func testLinesMatchesTheHeroFormula() {
        // `HomeHeroForeground.synopsisLineLimit`: floor((slot + 1) / lineHeight), at least 1.
        XCTAssertEqual(Long.lines(slot: 72, lineHeight: 30), 2)
        XCTAssertEqual(Long.lines(slot: 59.67, lineHeight: 30), 2)
        XCTAssertEqual(Long.lines(slot: 59.67, lineHeight: 31.32), 1)
        XCTAssertEqual(Long.lines(slot: 140, lineHeight: 30), 4)
        XCTAssertEqual(Long.lines(slot: 10, lineHeight: 30), 1)
    }

    func testSpendsSlackBeforeTheLogo() {
        // 3 lines of 30 need 89.25 − 72 = 17.25: all of it fits in 22 of slack.
        let g = Long.grant(slot: 72, standardLines: 2, logoSlot: 110, logoFloor: 64,
                           unusedSlack: 22, lineHeight: 30)
        XCTAssertEqual(g.lines, 4, "4 lines need 47.25 ≤ 22 + 46 available")
        XCTAssertEqual(g.synopsisGrowth, 47.25, accuracy: 0.001)
        XCTAssertEqual(g.slackSpent, 22, accuracy: 0.001)
        XCTAssertEqual(g.logoGive, 25.25, accuracy: 0.001)

        let slackOnly = Long.grant(slot: 72, standardLines: 2, logoSlot: 110, logoFloor: 110,
                                   unusedSlack: 22, lineHeight: 30)
        XCTAssertEqual(slackOnly.lines, 3)
        XCTAssertEqual(slackOnly.logoGive, 0, "the logo is untouched when slack covers the need")
    }

    func testTakesOnlyWhatTheNextLinesNeed() {
        // Room for 4 lines, but never more than 4 even with plenty left over.
        let g = Long.grant(slot: 72, standardLines: 2, logoSlot: 400, logoFloor: 0,
                           unusedSlack: 400, lineHeight: 30)
        XCTAssertEqual(g.lines, Long.maxLines)
        XCTAssertEqual(g.synopsisGrowth, 4 * 30 - 1 - 72 + Long.roundingMargin, accuracy: 0.001)
        XCTAssertEqual(g.logoGive, 0)
    }

    func testNoRoomKeepsStandard() {
        let g = Long.grant(slot: 59.67, standardLines: 1, logoSlot: 76, logoFloor: 76,
                           unusedSlack: 0, lineHeight: 31.32)
        XCTAssertFalse(g.isGrowing)
        XCTAssertEqual(g.lines, 1)
        XCTAssertEqual(g.logoGive, 0)
    }

    func testAtTheCapNothingIsSpent() {
        // The Show Hero OFF panel at Medium: 140 pt slot, 4 lines of 30 already.
        let g = Long.grant(slot: 140, standardLines: 4, logoSlot: 110, logoFloor: 64,
                           unusedSlack: 22, lineHeight: 30)
        XCTAssertFalse(g.isGrowing)
        XCTAssertEqual(g.lines, 4)
    }

    func testGrantedLinesAreTheLinesTheGrownSlotHolds() {
        for lh in Self.lineHeights {
            for slot in stride(from: CGFloat(36), through: 140, by: 0.5) {
                let standard = Long.lines(slot: slot, lineHeight: lh)
                let g = Long.grant(slot: slot, standardLines: standard, logoSlot: 110, logoFloor: 64,
                                   unusedSlack: 22, lineHeight: lh)
                XCTAssertEqual(Long.lines(slot: slot + g.synopsisGrowth, lineHeight: lh), g.lines,
                               "slot \(slot) lh \(lh)")
                XCTAssertGreaterThanOrEqual(g.lines, standard)
            }
        }
    }

    // MARK: - The pinned hero, every regime

    /// The BUG-87/89 guard: for every Poster Size × captions × hero form × zoom mode × font, Long
    /// fits inside the hero frame the rows' plan already sized (slack spent ≤ the frame's unused
    /// slack), keeps the logo at or above its floor, and never shows fewer lines than Standard.
    func testPinnedLongNeverOutgrowsTheFrame() {
        for poster in Self.sizes {
            for caption in [true, false] {
                for showsCTA in [true, false] {
                    for noZoom in [true, false] {
                        let plan = PinnedRowGeometry.plan(posterHeight: poster,
                                                          captionVisible: caption,
                                                          showsCTA: showsCTA,
                                                          landscapeRows: false,
                                                          mode: Self.mode(noZoom: noZoom),
                                                          titleHeight: PinnedRowGeometry.measuredTitleHeight)
                        let split = PinnedRowGeometry.HeroSlotGive.split(compression: plan.compression,
                                                                         showsCTA: showsCTA,
                                                                         folderHero: false)
                        let frame = Theme.Size.heroCarouselHeightPinned - plan.compression
                        let gaps: CGFloat = (showsCTA ? 3 : 2) * Theme.Size.heroPinnedSlotGap
                        let lowerSlots: CGFloat = showsCTA
                            ? Theme.Size.heroSynopsisSlotHeightPinned + Theme.Size.heroButtonSlotHeight
                            : Theme.Size.heroSynopsisSlotHeightPinnedPanel
                        let fixedSlots: CGFloat = 2 * Theme.Size.heroPinnedVerticalPad
                            + Theme.Size.heroLogoSlotHeightPinned
                            + Theme.Size.heroMetaSlotHeight
                        let standardContent: CGFloat = fixedSlots + gaps + lowerSlots - split.total
                        for lh in Self.lineHeights {
                            let g = Long.pinned(compression: plan.compression, showsCTA: showsCTA, lineHeight: lh)
                            let label = "poster \(Int(poster)) cap \(caption) cta \(showsCTA) noZoom \(noZoom) lh \(lh)"
                            let longContent = standardContent + g.synopsisGrowth - g.logoGive
                            XCTAssertLessThanOrEqual(longContent, frame + 0.001, label)
                            let logo = Theme.Size.heroLogoSlotHeightPinned - split.logo - g.logoGive
                            XCTAssertGreaterThanOrEqual(logo, Long.pinnedLogoFloor - 0.001, label)
                            let slot = (showsCTA ? Theme.Size.heroSynopsisSlotHeightPinned
                                                 : Theme.Size.heroSynopsisSlotHeightPinnedPanel) - split.synopsis
                            XCTAssertGreaterThanOrEqual(g.lines, Long.lines(slot: slot, lineHeight: lh), label)
                            XCTAssertLessThanOrEqual(g.lines, max(Long.maxLines, Long.lines(slot: slot, lineHeight: lh)), label)
                        }
                    }
                }
            }
        }
    }

    /// The reporter's shape: Large, Show Hero ON (pinned carousel), zoom on, Open Sans. Standard
    /// shows 1 line; Long gets the second by taking ≈2.2 pt of logo (76 → ≈73.8).
    func testStevensLargeZoomCarouselGetsASecondLine() {
        let plan = PinnedRowGeometry.plan(posterHeight: Self.large, captionVisible: false, showsCTA: true,
                                          landscapeRows: false, mode: Self.mode(noZoom: false),
                                          titleHeight: PinnedRowGeometry.measuredTitleHeight)
        let g = Long.pinned(compression: plan.compression, showsCTA: true, lineHeight: Self.openSansLine)
        XCTAssertEqual(g.lines, 2)
        XCTAssertEqual(g.slackSpent, 0, accuracy: 0.001, "the compression already spent the frame slack")
        XCTAssertLessThan(g.logoGive, 3)
    }

    /// Medium (no compression): the carousel goes from 2 to 4 lines, slack first, logo 110 → ≈85.
    func testMediumCarouselGoesToFourLines() {
        let g = Long.pinned(compression: 0, showsCTA: true, lineHeight: Self.systemLine)
        XCTAssertEqual(g.lines, 4)
        XCTAssertEqual(g.slackSpent, Theme.Size.heroPinnedFrameSlack, accuracy: 0.001)
        XCTAssertEqual(g.logoGive, 25.25, accuracy: 0.001)
    }

    /// The rows' plan does not read the setting: flipping it leaves every plan identical.
    func testPlanIgnoresTheSetting() {
        let key = PinnedRowGeometry.SynopsisLength.defaultsKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        func plans() -> [PinnedRowGeometry.Plan] {
            Self.sizes.flatMap { poster in
                [true, false].map { cta in
                    PinnedRowGeometry.plan(posterHeight: poster, captionVisible: true, showsCTA: cta,
                                           landscapeRows: false, mode: Self.mode(noZoom: false),
                                           titleHeight: PinnedRowGeometry.measuredTitleHeight)
                }
            }
        }
        UserDefaults.standard.set("standard", forKey: key)
        let standard = plans()
        UserDefaults.standard.set("long", forKey: key)
        XCTAssertEqual(plans(), standard)
    }

    // MARK: - The in-scroll Classic hero

    func testClassicFrameSlack() {
        XCTAssertEqual(Long.classicFrameSlack(showsCTA: true), 46, accuracy: 0.001)
    }

    func testClassicLongFitsTheFrame() {
        for lh in Self.lineHeights {
            let g = Long.classic(showsCTA: true, lineHeight: lh)
            XCTAssertEqual(g.lines, 4, "lh \(lh)")
            XCTAssertLessThanOrEqual(g.slackSpent, Long.classicFrameSlack(showsCTA: true) + 0.001)
            XCTAssertGreaterThanOrEqual(Theme.Size.heroLogoSlotHeight - g.logoGive, Long.classicLogoFloor)
        }
    }
}
