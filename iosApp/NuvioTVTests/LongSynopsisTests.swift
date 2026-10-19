import XCTest
import CoreGraphics
@testable import NuvioTV

/// FEAT-61 (Steven rc3) — the Classic hero's longer description, the line-budget math in
/// `PinnedRowGeometry.LongSynopsis`. Batch M D8 (Christian, 2026-10-19: "4 where it fits"): the
/// Synopsis Length setting is gone and Long is how Classic always draws.
///
/// Pure arithmetic, like `PinnedRowGeometryTests`. The invariant that matters for BUG-87/89 is that
/// Long never needs more height than the hero frame already has: the rows' plan is computed without
/// it, so as long as the grown content fits the unchanged frame, nothing below the hero can move.
/// What these tests cannot prove is how the text looks on the TV — that is the device pass.
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

    /// The rows' plan is pure and never reads the old Synopsis Length key: the same inputs give
    /// equal plans, and a stale `home_synopsis_length` value an older build left in the defaults
    /// changes nothing (the setting is gone, Batch M D8).
    func testPlanIsStable() {
        let staleKey = "home_synopsis_length"
        let saved = UserDefaults.standard.object(forKey: staleKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: staleKey) }
            else { UserDefaults.standard.removeObject(forKey: staleKey) }
        }
        func plans() -> [PinnedRowGeometry.Plan] {
            Self.sizes.flatMap { poster in
                [true, false].flatMap { cta in
                    [true, false].map { noZoom in
                        PinnedRowGeometry.plan(posterHeight: poster, captionVisible: true, showsCTA: cta,
                                               landscapeRows: false, mode: Self.mode(noZoom: noZoom),
                                               titleHeight: PinnedRowGeometry.measuredTitleHeight)
                    }
                }
            }
        }
        UserDefaults.standard.removeObject(forKey: staleKey)
        let baseline = plans()
        XCTAssertEqual(plans(), baseline, "the plan is pure")
        UserDefaults.standard.set("standard", forKey: staleKey)
        XCTAssertEqual(plans(), baseline)
        UserDefaults.standard.set("long", forKey: staleKey)
        XCTAssertEqual(plans(), baseline)
    }

    // MARK: - D8 line table

    /// The pinned hero's room for the synopsis with the logo at Long's floor, from the FRAME alone:
    /// `heroCarouselHeightPinned − compression`, minus the paddings, the gaps, the meta line, the
    /// CTA (carousel only) and `pinnedLogoFloor`. Independent of `LongSynopsis`'s slack/logo
    /// bookkeeping, so the table below checks that bookkeeping against the frame it must fit.
    private static func pinnedRoom(compression: CGFloat, showsCTA: Bool) -> CGFloat {
        let fixed: CGFloat = 2 * Theme.Size.heroPinnedVerticalPad
            + (showsCTA ? 3 : 2) * Theme.Size.heroPinnedSlotGap
            + Theme.Size.heroMetaSlotHeight
            + (showsCTA ? Theme.Size.heroButtonSlotHeight : 0)
        return Theme.Size.heroCarouselHeightPinned - max(compression, 0) - fixed - Long.pinnedLogoFloor
    }

    /// The in-scroll Classic hero's room: its synopsis slot, its unused frame slack and its logo
    /// slot down to `classicLogoFloor`.
    private static func classicRoom(showsCTA: Bool) -> CGFloat {
        Theme.Size.heroSynopsisSlotHeight + Long.classicFrameSlack(showsCTA: showsCTA)
            + Theme.Size.heroLogoSlotHeight - Long.classicLogoFloor
    }

    /// D8's rule on a room: 4 lines where they fit, else the most that do, never fewer than the
    /// count the hero draws without growing (`standard`).
    private static func expectedLines(room: CGFloat, standard: Int, lineHeight: CGFloat) -> Int {
        for target in stride(from: Long.maxLines, through: standard + 1, by: -1)
        where CGFloat(target) * lineHeight - Long.lineTolerance + Long.roundingMargin <= room + 0.001 {
            return target
        }
        return standard
    }

    /// Batch M D8 table: line counts per Poster Size (Small, Medium, Medium+, Large) × font
    /// (system, Open Sans) × form (pinned carousel, Show Hero OFF panel, in-scroll Classic hero),
    /// over both zoom modes and both caption states. Every cell shows 4 lines where the frame has
    /// room for them and the most that fit otherwise (Large may show fewer than 4); the frame never
    /// grows. The full table prints to the test log for the release notes.
    func testD8LineTable() {
        let names = ["Small", "Medium", "Medium+", "Large"]
        var table: [String] = []
        for (index, poster) in Self.sizes.enumerated() {
            for lh in Self.lineHeights {
                let font = lh == Self.systemLine ? "system" : "Open Sans"
                for showsCTA in [true, false] {
                    for noZoom in [true, false] {
                        for caption in [true, false] {
                            let plan = PinnedRowGeometry.plan(posterHeight: poster,
                                                              captionVisible: caption,
                                                              showsCTA: showsCTA,
                                                              landscapeRows: false,
                                                              mode: Self.mode(noZoom: noZoom),
                                                              titleHeight: PinnedRowGeometry.measuredTitleHeight)
                            let split = PinnedRowGeometry.HeroSlotGive.split(compression: plan.compression,
                                                                             showsCTA: showsCTA,
                                                                             folderHero: false)
                            let slot = (showsCTA ? Theme.Size.heroSynopsisSlotHeightPinned
                                                 : Theme.Size.heroSynopsisSlotHeightPinnedPanel) - split.synopsis
                            let standard = Long.lines(slot: slot, lineHeight: lh)
                            let g = Long.pinned(compression: plan.compression, showsCTA: showsCTA, lineHeight: lh)
                            let expected = Self.expectedLines(room: Self.pinnedRoom(compression: plan.compression,
                                                                                    showsCTA: showsCTA),
                                                              standard: standard, lineHeight: lh)
                            let form = showsCTA ? "carousel" : "panel"
                            let label = "\(names[index]) \(font) \(form) noZoom \(noZoom) cap \(caption)"
                                + " compression \(plan.compression)"
                            XCTAssertEqual(g.lines, expected, label)
                            XCTAssertLessThanOrEqual(g.lines, Long.maxLines, label)
                            if plan.compression <= 0 {
                                XCTAssertEqual(g.lines, Long.maxLines, "no compression leaves room for 4: \(label)")
                            }
                            table.append("\(label) → \(g.lines)")
                        }
                    }
                }
            }
        }
        for lh in Self.lineHeights {
            let font = lh == Self.systemLine ? "system" : "Open Sans"
            let g = Long.classic(showsCTA: true, lineHeight: lh)
            XCTAssertEqual(g.lines, Self.expectedLines(room: Self.classicRoom(showsCTA: true),
                                                       standard: 2, lineHeight: lh), "in-scroll \(font)")
            XCTAssertEqual(g.lines, Long.maxLines, "the in-scroll hero has room for 4: \(font)")
            table.append("any size \(font) in-scroll → \(g.lines)")
        }
        print("[LongSynopsisTests] D8 line table\n" + table.joined(separator: "\n"))
    }

    /// The anchors behind the table, worked by hand from the frame (system 30, Open Sans 31.32):
    /// the carousel's room is 140 − compression, so 4 lines need compression ≤ 20.75 (system) or
    /// ≤ 15.47 (Open Sans), 3 lines ≤ 50.75 / 46.79, and Large's 68.33 leaves 2.
    func testD8CarouselAnchors() {
        XCTAssertEqual(Long.pinned(compression: 0, showsCTA: true, lineHeight: Self.systemLine).lines, 4)
        XCTAssertEqual(Long.pinned(compression: 0, showsCTA: true, lineHeight: Self.openSansLine).lines, 4)
        XCTAssertEqual(Long.pinned(compression: 16, showsCTA: true, lineHeight: Self.systemLine).lines, 4)
        XCTAssertEqual(Long.pinned(compression: 16, showsCTA: true, lineHeight: Self.openSansLine).lines, 3)
        XCTAssertEqual(Long.pinned(compression: 68.33, showsCTA: true, lineHeight: Self.systemLine).lines, 2)
        XCTAssertEqual(Long.pinned(compression: 68.33, showsCTA: true, lineHeight: Self.openSansLine).lines, 2)
        XCTAssertEqual(Long.pinned(compression: 0, showsCTA: false, lineHeight: Self.systemLine).lines, 4)
        XCTAssertEqual(Long.pinned(compression: 0, showsCTA: false, lineHeight: Self.openSansLine).lines, 4)
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
