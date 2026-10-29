import XCTest
import UIKit
@testable import NuvioTV

/// Home Stage & Strip (H9, FEAT-45; P4 spec §7.2): the navigation chrome's mode and visibility
/// resolution, the one-time `sidebar_style` migration, the Always Visible inset math and the
/// clearance it guarantees, and the DEBUG content-gate knob. Every defaults test uses its own
/// throwaway `UserDefaults` suite (its persistent domain is the suite name), never `.standard`.
@MainActor
final class NavigationChromeTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) rethrows {
        let suite = "NavigationChromeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, suite)
    }

    // MARK: Keys and resolution

    func testKeysAreTheDeviceLocalOnes() {
        XCTAssertEqual(NavigationChrome.styleKey, "sidebar_style", "kept from FEAT-30 so the stored choice survives")
        XCTAssertEqual(NavigationChrome.railVisibilityKey, "rail_visibility")
        XCTAssertEqual(NavigationChrome.legacySidebarValue, "sidebar")
        XCTAssertEqual(NavigationChrome.Style.tabs.rawValue, "tabs")
        XCTAssertEqual(NavigationChrome.Style.rail.rawValue, "rail")
        XCTAssertEqual(NavigationChrome.RailVisibility.always.rawValue, "always")
        XCTAssertEqual(NavigationChrome.RailVisibility.whileBrowsing.rawValue, "browsing")
        XCTAssertEqual(NavigationChrome.RailVisibility.hidden.rawValue, "hidden")
    }

    func testStyleResolution() {
        XCTAssertEqual(NavigationChrome.style(raw: "tabs"), .tabs)
        XCTAssertEqual(NavigationChrome.style(raw: "rail"), .rail)
        XCTAssertEqual(NavigationChrome.style(raw: "sidebar"), .rail, "FEAT-30's stored value reads as Rail")
        XCTAssertEqual(NavigationChrome.style(raw: nil), .tabs)
        XCTAssertEqual(NavigationChrome.style(raw: ""), .tabs)
        XCTAssertEqual(NavigationChrome.style(raw: "garbage"), .tabs)
        XCTAssertEqual(NavigationChrome.style(raw: " Rail "), .rail, "a hand-typed launch argument still resolves")
    }

    func testVisibilityResolution() {
        XCTAssertEqual(NavigationChrome.railVisibility(raw: "browsing"), .whileBrowsing)
        XCTAssertEqual(NavigationChrome.railVisibility(raw: "always"), .always)
        XCTAssertEqual(NavigationChrome.railVisibility(raw: nil), .always)
        XCTAssertEqual(NavigationChrome.railVisibility(raw: "garbage"), .always)
        XCTAssertEqual(NavigationChrome.railVisibility(raw: "hidden"), .hidden, "FEAT-62")
        XCTAssertEqual(NavigationChrome.railVisibility(raw: " Hidden "), .hidden, "a hand-typed launch argument")
    }

    func testModeReadsTheKeys() {
        withDefaults { defaults, _ in
            XCTAssertEqual(NavigationChrome.style(defaults), .tabs, "an untouched install is Tabs")
            XCTAssertFalse(NavigationChrome.isRail(defaults))
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults))

            defaults.set("rail", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.isRail(defaults))
            XCTAssertEqual(NavigationChrome.railVisibility(defaults), .always, "Always Visible is the default")
            XCTAssertTrue(NavigationChrome.reservesWidth(defaults))

            defaults.set("browsing", forKey: NavigationChrome.railVisibilityKey)
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults))

            defaults.set("hidden", forKey: NavigationChrome.railVisibilityKey)
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults), "FEAT-62: Hidden reserves nothing")

            defaults.set("sidebar", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.isRail(defaults))

            defaults.set("tabs", forKey: NavigationChrome.styleKey)
            defaults.set("always", forKey: NavigationChrome.railVisibilityKey)
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults), "Tabs mode never reserves width")
        }
    }

    // MARK: Migration (R6)

    func testMigratedValueIsExactlyForSidebar() {
        XCTAssertEqual(NavigationChrome.migratedValue(forPersisted: "sidebar"), "rail")
        XCTAssertNil(NavigationChrome.migratedValue(forPersisted: "rail"))
        XCTAssertNil(NavigationChrome.migratedValue(forPersisted: "tabs"))
        XCTAssertNil(NavigationChrome.migratedValue(forPersisted: nil))
        XCTAssertNil(NavigationChrome.migratedValue(forPersisted: "Sidebar"), "exact match only")
        XCTAssertNil(NavigationChrome.migratedValue(forPersisted: 1))
    }

    func testMigrationRewritesSidebarToRail() {
        withDefaults { defaults, suite in
            defaults.set("sidebar", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertEqual(defaults.string(forKey: NavigationChrome.styleKey), "rail")
            XCTAssertTrue(NavigationChrome.isRail(defaults))
        }
    }

    func testMigrationLeavesRailAndTabsAlone() {
        for value in ["rail", "tabs"] {
            withDefaults { defaults, suite in
                defaults.set(value, forKey: NavigationChrome.styleKey)
                XCTAssertFalse(NavigationChrome.migrateLegacy(defaults, domain: suite), value)
                XCTAssertEqual(defaults.string(forKey: NavigationChrome.styleKey), value)
            }
        }
    }

    func testMigrationLeavesAMissingKeyMissing() {
        withDefaults { defaults, suite in
            XCTAssertFalse(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertNil(defaults.object(forKey: NavigationChrome.styleKey))
        }
    }

    func testMigrationLeavesGarbageUnchanged() {
        withDefaults { defaults, suite in
            defaults.set("floating", forKey: NavigationChrome.styleKey)
            XCTAssertFalse(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertEqual(defaults.string(forKey: NavigationChrome.styleKey), "floating")
        }
    }

    func testMigrationSecondRunIsANoOp() {
        withDefaults { defaults, suite in
            defaults.set("sidebar", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertFalse(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertEqual(defaults.string(forKey: NavigationChrome.styleKey), "rail")
        }
    }

    func testMigrationNeverTouchesRailVisibility() {
        withDefaults { defaults, suite in
            defaults.set("sidebar", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertNil(defaults.object(forKey: NavigationChrome.railVisibilityKey),
                         "an untouched visibility stays unset (Always Visible)")

            defaults.set("browsing", forKey: NavigationChrome.railVisibilityKey)
            defaults.set("sidebar", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.migrateLegacy(defaults, domain: suite))
            XCTAssertEqual(defaults.string(forKey: NavigationChrome.railVisibilityKey), "browsing")
        }
    }

    func testMigrationWithoutADomainDoesNothing() {
        withDefaults { defaults, _ in
            defaults.set("sidebar", forKey: NavigationChrome.styleKey)
            XCTAssertFalse(NavigationChrome.migrateLegacy(defaults, domain: ""))
            XCTAssertEqual(defaults.string(forKey: NavigationChrome.styleKey), "sidebar")
        }
    }

    // MARK: Inset math (R3, §1.2)

    func testReservedEdgeAndPill() {
        XCTAssertEqual(NavigationChrome.reservedEdge, 116, "16 bezel + 84 pill + 16 gap")
        XCTAssertEqual(NavigationChrome.pillTrailingEdge, 100)
    }

    func testContentSafeAreaExtra() {
        XCTAssertEqual(NavigationChrome.contentSafeAreaExtra(sideSafeArea: 80, reservesWidth: true, position: .centre), 36)
        XCTAssertEqual(NavigationChrome.contentSafeAreaExtra(sideSafeArea: 80, reservesWidth: false, position: .centre), 0)
        XCTAssertEqual(NavigationChrome.contentSafeAreaExtra(sideSafeArea: 116, reservesWidth: true, position: .centre), 0)
        XCTAssertEqual(NavigationChrome.contentSafeAreaExtra(sideSafeArea: 130, reservesWidth: true, position: .centre), 0, "never negative")
    }

    func testContentLeading() {
        XCTAssertEqual(NavigationChrome.contentLeading(sideSafeArea: 80, reservesWidth: true, position: .centre), 176)
        XCTAssertEqual(NavigationChrome.contentLeading(sideSafeArea: 80, reservesWidth: false, position: .centre), 140)
    }

    func testRowEdgeMargins() {
        XCTAssertEqual(NavigationChrome.rowEdgeMargins(sideSafeArea: 80, reservesWidth: true, position: .centre),
                       RowEdgeMargins(leading: 176, trailing: 140))
        XCTAssertEqual(NavigationChrome.rowEdgeMargins(sideSafeArea: 80, reservesWidth: false, position: .centre),
                       RowEdgeMargins(leading: 140, trailing: 140))
        // Production passes the session's side safe area: no reserved width is exactly `.standard`.
        XCTAssertEqual(NavigationChrome.rowEdgeMargins(sideSafeArea: PinnedRowGeometry.sideSafeArea, reservesWidth: false, position: .centre),
                       RowEdgeMargins.standard)
    }

    /// §1.2 clearance: the widest row lift (a Saga card, ≈30 pt per side) never reaches under the
    /// pill. Always Visible: 176 − 30 ≥ 116. Hide While Browsing: 140 − 30 > 100.
    func testFirstCardLiftClearsThePill() {
        let lift = NavigationChrome.widestRowLiftOverhang
        XCTAssertEqual(lift, 30, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(NavigationChrome.contentLeading(sideSafeArea: 80, reservesWidth: true, position: .centre) - lift,
                                    NavigationChrome.reservedEdge)
        XCTAssertGreaterThan(NavigationChrome.contentLeading(sideSafeArea: 80, reservesWidth: false, position: .centre) - lift,
                             NavigationChrome.pillTrailingEdge)
    }

    // MARK: Search keyboard inset (B4)

    func testReservedLeadingInsetCollapsesOnlyForTheSearchKeyboard() {
        func inset(_ visibility: NavigationChrome.RailVisibility, tab: Int, kb: Bool, hold: Bool = false) -> CGFloat {
            RailVisibilityRule.reservedLeadingInset(sideSafeArea: 80, visibility: visibility, position: .centre,
                                                    selectedTab: tab, keyboardFocused: kb, holdInset: hold)
        }
        XCTAssertEqual(inset(.always, tab: 1, kb: false), 36)
        XCTAssertEqual(inset(.always, tab: 1, kb: true), 0, "Search keyboard: the content takes the width")
        XCTAssertEqual(inset(.always, tab: 0, kb: true), 36, "the flag means nothing off Search")
        XCTAssertEqual(inset(.always, tab: 1, kb: true, hold: true), 36, "the A/B knob holds the inset")
        XCTAssertEqual(inset(.whileBrowsing, tab: 1, kb: true), 0)
        XCTAssertEqual(inset(.whileBrowsing, tab: 0, kb: false), 0)
        XCTAssertEqual(inset(.hidden, tab: 0, kb: false), 0, "FEAT-62")
        XCTAssertEqual(inset(.hidden, tab: 1, kb: true, hold: true), 0)
    }

    func testKeyboardHidesRailOnlyOnSearch() {
        XCTAssertTrue(RailVisibilityRule.keyboardHidesRail(selectedTab: RailVisibilityRule.searchTab, keyboardFocused: true))
        XCTAssertFalse(RailVisibilityRule.keyboardHidesRail(selectedTab: RailVisibilityRule.searchTab, keyboardFocused: false))
        XCTAssertFalse(RailVisibilityRule.keyboardHidesRail(selectedTab: 0, keyboardFocused: true))
    }

    func testSearchInsetHoldKnobKey() {
        XCTAssertEqual(RailSearchInsetHold.defaultsKey, "debug.railSearchInsetHold")
    }

    // MARK: Content gate knob (DEBUG A/B)

    func testRailGateModeResolution() {
        XCTAssertEqual(RailGateMode.resolve(nil), .uikit, "the primary is the default")
        XCTAssertEqual(RailGateMode.resolve("uikit"), .uikit)
        XCTAssertEqual(RailGateMode.resolve("perTab"), .perTab)
        XCTAssertEqual(RailGateMode.resolve("PERTAB"), .perTab)
        XCTAssertEqual(RailGateMode.resolve(" per-tab "), .perTab)
        XCTAssertEqual(RailGateMode.resolve("disabled"), .uikit)
        XCTAssertEqual(RailGateMode.defaultsKey, "debug.railGate")
    }

    // FEAT-80 (Steven rc7): rail position and labels resolve to today's rail unless set.
    func testRailPositionResolution() {
        XCTAssertEqual(NavigationChrome.railPosition(raw: nil), .centre)
        XCTAssertEqual(NavigationChrome.railPosition(raw: "centre"), .centre)
        XCTAssertEqual(NavigationChrome.railPosition(raw: " Top "), .corner, "FEAT-80 Batch N: rc8's Top reads as Corner")
        XCTAssertEqual(NavigationChrome.railPosition(raw: "top"), .corner)
        XCTAssertEqual(NavigationChrome.railPosition(raw: "corner"), .corner)
        XCTAssertEqual(NavigationChrome.railPosition(raw: " Corner "), .corner, "a hand-typed launch argument")
        XCTAssertEqual(NavigationChrome.railPosition(raw: "bottom"), .centre)
        XCTAssertEqual(NavigationChrome.railPosition(raw: ""), .centre)
        XCTAssertEqual(NavigationChrome.RailPosition.corner.rawValue, "corner")
        XCTAssertEqual(NavigationChrome.RailPosition.allCases, [.centre, .corner], "Settings lists exactly these two")
    }

    // MARK: Corner reserves nothing (FEAT-80, Batch N)

    func testRailPositionReadsTheKeyWithoutWriting() {
        withDefaults { defaults, suite in
            XCTAssertEqual(NavigationChrome.railPosition(defaults), .centre, "an untouched install is Centre")
            defaults.set("top", forKey: NavigationChrome.railPositionKey)
            XCTAssertEqual(NavigationChrome.railPosition(defaults), .corner)
            XCTAssertEqual(defaults.persistentDomain(forName: suite)?[NavigationChrome.railPositionKey] as? String, "top",
                           "the stored rc8 value is left alone: no migration write")
        }
    }

    func testCornerReservesNoWidth() {
        withDefaults { defaults, _ in
            defaults.set("rail", forKey: NavigationChrome.styleKey)
            XCTAssertTrue(NavigationChrome.reservesWidth(defaults), "Centre + Always Visible reserves")
            defaults.set("corner", forKey: NavigationChrome.railPositionKey)
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults), "Corner + Always Visible reserves nothing")
            defaults.set("top", forKey: NavigationChrome.railPositionKey)
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults), "a stored Top is Corner")
            defaults.set("browsing", forKey: NavigationChrome.railVisibilityKey)
            XCTAssertFalse(NavigationChrome.reservesWidth(defaults))
        }
        XCTAssertTrue(NavigationChrome.reservesWidth(visibility: .always, position: .centre))
        XCTAssertFalse(NavigationChrome.reservesWidth(visibility: .always, position: .corner))
        XCTAssertFalse(NavigationChrome.reservesWidth(visibility: .whileBrowsing, position: .centre))
        XCTAssertFalse(NavigationChrome.reservesWidth(visibility: .hidden, position: .corner))
    }

    func testCornerInsetMathIsZero() {
        XCTAssertEqual(NavigationChrome.contentSafeAreaExtra(sideSafeArea: 80, reservesWidth: true, position: .corner), 0)
        XCTAssertEqual(NavigationChrome.contentSafeAreaExtra(sideSafeArea: 80, reservesWidth: false, position: .corner), 0)
        XCTAssertEqual(NavigationChrome.contentLeading(sideSafeArea: 80, reservesWidth: true, position: .corner), 140)
        XCTAssertEqual(NavigationChrome.rowEdgeMargins(sideSafeArea: 80, reservesWidth: true, position: .corner),
                       RowEdgeMargins(leading: 140, trailing: 140))
        XCTAssertEqual(NavigationChrome.rowEdgeMargins(sideSafeArea: PinnedRowGeometry.sideSafeArea, reservesWidth: true,
                                                       position: .corner),
                       RowEdgeMargins.standard, "Corner rows keep the standard margins")
    }

    func testCornerShellInsetIsZeroInEveryVisibility() {
        for visibility in [NavigationChrome.RailVisibility.always, .whileBrowsing, .hidden] {
            for (tab, kb, hold) in [(0, false, false), (1, false, false), (1, true, false), (1, true, true)] {
                XCTAssertEqual(RailVisibilityRule.reservedLeadingInset(sideSafeArea: 80, visibility: visibility,
                                                                       position: .corner, selectedTab: tab,
                                                                       keyboardFocused: kb, holdInset: hold), 0,
                               "Corner \(visibility) tab=\(tab) kb=\(kb) hold=\(hold)")
            }
        }
    }

    /// W3-11 (D1): the Corner rail's ITEMS keep Batch O's place. The column sits at Centre's bezel
    /// inset whatever the Rail Style, anchored so its Home cell (the first row, one
    /// `verticalPadding` below the column's top, the mirror `RailMetrics` reads) lands on the tvOS
    /// top safe-area line: the Home cell at (28, 60). Review r1 P3-2: the column's top is derived
    /// from the safe-area line and the padding, never a literal of its own. Its GLASS is flush:
    /// from the screen corner, past the top and the left edges by the bleed, open or not, in both
    /// label modes, and always around the Home cell.
    func testCornerPillGeometry() {
        XCTAssertEqual(NavigationChrome.cornerSafeTop, 60, "the tvOS top safe-area line on a 1920 × 1080 canvas")
        XCTAssertEqual(NavigationChrome.cornerPillTop + NavigationChrome.verticalPadding, NavigationChrome.cornerSafeTop,
                       "the Home cell sits one vertical padding below the column's top, on the safe-area line")
        XCTAssertEqual(NavigationChrome.cornerPillTop, 38)
        XCTAssertEqual(NavigationChrome.bezelInset + NavigationChrome.innerPadding, 28,
                       "the Home cell's leading edge: Centre's bezel inset plus the column's padding")
        let homeCell = CGRect(x: NavigationChrome.bezelInset + NavigationChrome.innerPadding, y: NavigationChrome.cornerSafeTop,
                              width: NavigationChrome.itemPlatter, height: NavigationChrome.itemPlatter)
        XCTAssertEqual(homeCell, CGRect(x: 28, y: 60, width: 60, height: 60))
        XCTAssertEqual(NavigationChrome.cornerBleed, 8)
        XCTAssertEqual(NavigationChrome.cornerRadius, 42, "the one rounded corner keeps Centre's radius")
        XCTAssertEqual(NavigationChrome.cornerRestHeight, 104, "60 + 2 × 22: the column around the Home cell alone")
        for labels in [true, false] {
            for open in [true, false] {
                let glass = NavigationChrome.cornerGlassFrame(labels: labels, open: open, columnHeight: 492)
                let step = "labels=\(labels) open=\(open): \(glass)"
                XCTAssertEqual(glass.origin, CGPoint(x: -NavigationChrome.cornerBleed, y: -NavigationChrome.cornerBleed),
                               "flush: drawn from the screen corner, the bleed past both edges, \(step)")
                XCTAssertLessThan(glass.minX, 0, "flush past the left edge, never a gap: \(step)")
                XCTAssertLessThan(glass.minY, 0, "flush past the top edge, never a gap: \(step)")
                XCTAssertTrue(glass.contains(homeCell), "the glass always holds the Home cell: \(step)")
                XCTAssertGreaterThanOrEqual(glass.maxY - homeCell.maxY, NavigationChrome.verticalPadding,
                                            "a vertical padding below the Home cell at least: \(step)")
            }
        }
        XCTAssertEqual(NavigationChrome.collapsedWidth, 84, "Corner's Icons Only width is Centre's")
        XCTAssertEqual(NavigationChrome.expandedWidth, 300, "Corner's Labels Shown width is Centre's")
    }

    /// W3-11, Labels Shown: the arm shows a flush top bar 316 × 142 on screen (324 × 150 with the
    /// bleed); the grow only lengthens it, to the column + 38. Its width never follows `open`, so
    /// nothing grows sideways. Five tabs plus the avatar: 6 × 60 + 5 × 14 + 18 + 2 × 22 = 492.
    func testCornerGlassFrameLabelsShown() {
        let rest = NavigationChrome.cornerGlassFrame(labels: true, open: false, columnHeight: 492)
        XCTAssertEqual(rest, CGRect(x: -8, y: -8, width: 324, height: 150))
        XCTAssertEqual(rest.maxX, 316, "on screen: 16 + 300 wide")
        XCTAssertEqual(rest.maxY, 142, "on screen: 38 + 104 tall")
        let open = NavigationChrome.cornerGlassFrame(labels: true, open: true, columnHeight: 492)
        XCTAssertEqual(open, CGRect(x: -8, y: -8, width: 324, height: 538))
        XCTAssertEqual(open.maxY, 530, "on screen: the column + 38")
        XCTAssertEqual(open.origin, rest.origin, "the unroll never moves the glass's origin")
        XCTAssertEqual(open.width, rest.width, "the width is independent of open: downward only")
        XCTAssertGreaterThan(open.height, rest.height, "only the height grows")
    }

    /// W3-11, Icons Only: 100 × 142 on screen at the arm (108 × 150 with the bleed), then the
    /// column + 38, the same 100 wide.
    func testCornerGlassFrameIconsOnly() {
        let rest = NavigationChrome.cornerGlassFrame(labels: false, open: false, columnHeight: 492)
        XCTAssertEqual(rest, CGRect(x: -8, y: -8, width: 108, height: 150))
        XCTAssertEqual(rest.maxX, 100, "on screen: 16 + 84 wide")
        let open = NavigationChrome.cornerGlassFrame(labels: false, open: true, columnHeight: 492)
        XCTAssertEqual(open, CGRect(x: -8, y: -8, width: 108, height: 538))
        XCTAssertEqual(open.width, rest.width, "the width is independent of open: downward only")
        XCTAssertGreaterThan(open.height, rest.height, "only the height grows")
    }

    /// The height follows the measured column once open (Discover's own tab adds a row: 7 × 60 +
    /// 6 × 14 + 18 + 44 = 566), never drops below the top bar (0 = not yet measured), and is
    /// ignored closed.
    func testCornerGlassFrameHeight() {
        XCTAssertEqual(NavigationChrome.cornerGlassFrame(labels: true, open: true, columnHeight: 566).maxY, 604)
        XCTAssertEqual(NavigationChrome.cornerGlassFrame(labels: true, open: true, columnHeight: 0),
                       NavigationChrome.cornerGlassFrame(labels: true, open: false, columnHeight: 0),
                       "floored at the top bar before the first measurement")
        XCTAssertEqual(NavigationChrome.cornerGlassFrame(labels: false, open: false, columnHeight: 566),
                       NavigationChrome.cornerGlassFrame(labels: false, open: false, columnHeight: 492),
                       "closed, the column's height plays no part")
    }

    func testRailLabelsResolution() {
        XCTAssertEqual(NavigationChrome.railLabels(raw: nil), .shown)
        XCTAssertEqual(NavigationChrome.railLabels(raw: "shown"), .shown)
        XCTAssertEqual(NavigationChrome.railLabels(raw: "ICONS"), .iconsOnly)
        XCTAssertEqual(NavigationChrome.railLabels(raw: "none"), .shown)
    }

    // MARK: Batch P (P2 Rail Style, P3/P10 glass variant)

    func testRailStyleResolution() {
        XCTAssertEqual(NavigationChrome.railStyle(raw: nil), .floating)
        XCTAssertEqual(NavigationChrome.railStyle(raw: ""), .floating)
        XCTAssertEqual(NavigationChrome.railStyle(raw: "floating"), .floating)
        XCTAssertEqual(NavigationChrome.railStyle(raw: "edge"), .edge)
        XCTAssertEqual(NavigationChrome.railStyle(raw: " EDGE "), .edge)
        XCTAssertEqual(NavigationChrome.railStyle(raw: "flush"), .floating)
    }

    func testPillLeadingByStyle() {
        XCTAssertEqual(NavigationChrome.pillLeading(.floating), 16)
        XCTAssertEqual(NavigationChrome.pillLeading(.edge), 0)
    }

    /// Edge must not move content: the reserved width never derives from `pillLeading`.
    func testReservedEdgeIgnoresStyle() {
        XCTAssertEqual(NavigationChrome.reservedEdge, 116)
        XCTAssertEqual(NavigationChrome.pillTrailingEdge, 100)
    }
}
