import Foundation
import UIKit   // UIFocusHeading only

// Home Stage & Strip (H9, FEAT-45; P4 spec §1.1): the navigation chrome's pure half. Everything in
// this file is a value or a function of values, unit-tested by `NavigationChromeTests` and
// `RailFocusPolicyTests`. The view (`NavigationRail`), its model and the shell wiring live in
// `NavigationRail.swift`.

// MARK: - Mode, visibility, migration, inset math

/// Which navigation chrome the tab shell shows: the system's top tab bar (Tabs, the default) or the
/// floating pill rail on the left (Rail). Rail replaced FEAT-30's Menu-revealed Sidebar mode.
///
/// Both keys are DEVICE-LOCAL `UserDefaults` strings, never synced (no reference in `shared/` or in
/// any sync blob): which chrome a living-room TV shows is a per-device display preference.
///
/// EVERY read of the mode must resolve to Tabs on an untouched install, and everything the rail adds
/// is structurally absent then: the call sites branch `if NavigationChrome.isRail() { … } else
/// { content }` rather than passing an inert value into an always-applied modifier, so Tabs mode
/// stays byte-identical. Reads are live (a `UserDefaults` lookup), never launch-latched: the mode
/// changes only across `ContentView`'s `.id(theme|style|visibility|font)` remount, and a remount
/// re-creates views, not type storage, so a latched `static let` would leave the shell half switched.
nonisolated enum NavigationChrome {
    /// Kept from FEAT-30 so the stored choice survives the rename.
    static let styleKey = "sidebar_style"
    /// New with the rail: Always Visible / Hide While Browsing / Hidden (FEAT-62).
    static let railVisibilityKey = "rail_visibility"
    /// FEAT-80 (Steven rc7): where the pill sits on the left edge, and whether it shows labels.
    /// Device-local like the two keys above.
    static let railPositionKey = "rail_position"
    static let railLabelsKey = "rail_labels"
    /// Batch P (P2, Steven rc10 photo 1): Floating (the default pill, `bezelInset` off the edge) or
    /// Edge (flat against the left screen edge, square outer corners). Device-local like the keys
    /// above. Never changes the reserved width, so it needs no remount.
    static let railStyleKey = "rail_style"
    /// FEAT-30's stored value. Reads as Rail, and `migrateLegacy` rewrites it once.
    static let legacySidebarValue = "sidebar"

    enum Style: String, Equatable, Sendable {
        case tabs
        case rail
    }

    enum RailVisibility: String, Equatable, Sendable {
        case always
        case whileBrowsing = "browsing"
        /// FEAT-62 (Steven, beta.19-rc3 follow-up 2026-10-08: "hide it on the first line, show it on
        /// Left/Back"): the rail is off screen at rest everywhere, Home's row 0 included, and only a
        /// reveal shows it (Left from the first card, through the failed-move arm, or Menu). It hides
        /// again as soon as focus leaves it. Reserves no width, like Hide While Browsing.
        case hidden
    }

    /// FEAT-80: Centre (the default, the pill vertically centred on the left edge) or Corner
    /// (Batch N; redesigned in Batch O, Christian's 2026-10-20 mock; W3-11, D1): a bare Home icon
    /// at the top-left that, when the rail opens, becomes Centre's column under a glass flush with
    /// the top and the left screen edges, unrolling downward only (`cornerGlassFrame`). Corner
    /// ignores the Rail Style. Corner replaced rc8's Top, which still reads as Corner
    /// (`railPosition(raw:)`), so no stored value needs a write.
    enum RailPosition: String, Equatable, Sendable, CaseIterable {
        case centre
        case corner
    }

    /// rc8's stored Top value. Resolves to Corner.
    static let legacyTopPositionValue = "top"

    /// FEAT-80: Shown (the default; the pill grows to show labels when it opens) or Icons Only (the
    /// pill keeps its collapsed width and never draws labels).
    enum RailLabels: String, Equatable, Sendable, CaseIterable {
        case shown
        case iconsOnly = "icons"
    }

    /// Batch P (P2): Floating (the default) or Edge (flush with the screen's left edge).
    enum RailStyle: String, Equatable, Sendable, CaseIterable {
        case floating
        case edge
    }

    /// Only "edge" is Edge (trimmed, case-insensitive); anything else keeps today's Floating pill.
    static func railStyle(raw: String?) -> RailStyle {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == RailStyle.edge.rawValue ? .edge : .floating
    }

    /// The pill's leading edge from the screen edge: `bezelInset` Floating, 0 Edge. `reservedEdge`
    /// and `pillTrailingEdge` deliberately do NOT derive from it (Edge must not move content).
    /// Centre only: Corner's column always sits at `bezelInset` (W3-11), its glass flush anyway.
    static func pillLeading(_ style: RailStyle) -> CGFloat {
        style == .edge ? 0 : bezelInset
    }

    /// "corner", and rc8's "top", read as Corner (FEAT-80, Batch N); anything else (missing,
    /// "centre", unknown) is Centre, so an untouched install keeps today's rail.
    static func railPosition(raw: String?) -> RailPosition {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case RailPosition.corner.rawValue?, legacyTopPositionValue?: return .corner
        default: return .centre
        }
    }

    static func railPosition(_ defaults: UserDefaults = .standard) -> RailPosition {
        railPosition(raw: defaults.string(forKey: railPositionKey))
    }

    /// Anything but "icons" is Shown, so a missing or unknown value keeps today's rail.
    static func railLabels(raw: String?) -> RailLabels {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == RailLabels.iconsOnly.rawValue ? .iconsOnly : .shown
    }

    /// FEAT-80 Corner (Batch O): the tvOS top safe-area line on a 1920 × 1080 canvas. The Home
    /// cell lands on it, at rest (the bare glyph) and open (the column's first row).
    static let cornerSafeTop: CGFloat = 60
    /// The Corner column's top edge (38): `cornerSafeTop` less the column's `verticalPadding`, so
    /// the Home cell sits on the safe-area line. Leading, the column sits at `bezelInset` whatever
    /// the Rail Style (W3-11, D1: Corner ignores Edge), so the Home cell is at (28, 60). This
    /// places the ITEMS only. The glass is no longer a pill around them: it is flush with the top
    /// AND the left screen edges, drawn from the screen corner past both (`cornerGlassFrame`), and
    /// only its height grows.
    static let cornerPillTop: CGFloat = cornerSafeTop - verticalPadding
    /// W3-11 (D1, Steven's 2026-10-19 mock): how far Corner's glass and its mask reach past the top
    /// and the left screen edges, so the Liquid Glass rim on those two sides lands off-canvas.
    static let cornerBleed: CGFloat = 8
    /// The Corner glass's one rounded corner, the bottom trailing one: Centre's pill radius
    /// (`pillRadius`, review r1 P3-6), so the two cannot drift apart.
    static let cornerRadius: CGFloat = pillRadius
    /// The Corner column's height around the Home cell alone: `itemPlatter` + 2 × `verticalPadding`
    /// = 104. The glass's height at rest and in phase 1 (the arm), before the grow.
    static let cornerRestHeight: CGFloat = itemPlatter + 2 * verticalPadding

    /// W3-11 (D1): the Corner glass's frame in SCREEN coordinates, bleed included, which the glass
    /// and its mask both draw at. Origin (−bleed, −bleed); width `bezelInset` + the column's width
    /// (300 with labels, 84 Icons Only) + the bleed, the same whether open or not, so the glass only
    /// ever grows DOWNWARD; height `cornerPillTop` + the column's height (`cornerRestHeight` until
    /// open, then `columnHeight`, never less than the rest height) + the bleed. On screen that is a
    /// flush top bar of 316 × 142 (100 × 142 Icons Only) that unrolls to the column + 38.
    static func cornerGlassFrame(labels: Bool, open: Bool, columnHeight: CGFloat) -> CGRect {
        let width = labels ? expandedWidth : collapsedWidth
        let height = open ? max(columnHeight, cornerRestHeight) : cornerRestHeight
        return CGRect(x: -cornerBleed, y: -cornerBleed,
                      width: bezelInset + width + cornerBleed,
                      height: cornerPillTop + height + cornerBleed)
    }

    // MARK: Layout numbers the math needs (mirrors of `RailMetrics`, NavigationRail.swift)

    /// The pill's leading edge from the screen edge (P4 R3; kept for this beta, critique Q6).
    static let bezelInset: CGFloat = 16
    /// The collapsed pill's width.
    static let collapsedWidth: CGFloat = 84
    /// The open pill's width with labels shown (Corner's glass width with labels, W3-11).
    static let expandedWidth: CGFloat = 300
    /// The circle behind each glyph, one rail row's height.
    static let itemPlatter: CGFloat = 60
    /// Centre's pill corner radius, the one literal: `RailMetrics.cornerRadius` (Centre's pill)
    /// and `cornerRadius` (Corner's one rounded corner, W3-11) both read it.
    static let pillRadius: CGFloat = 42
    /// The column's padding beside its rows: the Home cell sits `bezelInset + innerPadding` = 28
    /// from the left screen edge.
    static let innerPadding: CGFloat = 12
    /// The pill's padding above its first item and below the profile avatar (FEAT-80 Corner's
    /// `cornerPillTop` is derived from it).
    static let verticalPadding: CGFloat = 22
    /// The gap the rail keeps from content when it reserves width.
    static let contentGap: CGFloat = 16
    /// `bezelInset + collapsedWidth + contentGap`: what Always Visible reserves from the bezel.
    static let reservedEdge: CGFloat = bezelInset + collapsedWidth + contentGap
    /// The collapsed pill's trailing edge (x = 100 on a 1920 canvas).
    static let pillTrailingEdge: CGFloat = bezelInset + collapsedWidth
    /// The widest focus lift a row card draws past its leading edge: a 500 pt Saga card under the
    /// measured system lift (≈1.1212, `PosterCard.swift`) grows ≈30 pt per side. The clearance test
    /// checks that a lifted first card never reaches under the pill in either visibility.
    static let widestRowLiftOverhang: CGFloat = 30

    // MARK: Resolution

    /// "rail", and FEAT-30's "sidebar", read as Rail; anything else (missing, "tabs", a corrupted
    /// or future string) is Tabs, never an unknown third state. Trimmed and lower-cased so a
    /// hand-typed launch argument (`-sidebar_style Rail`) still resolves.
    static func style(raw: String?) -> Style {
        guard let raw else { return .tabs }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case Style.rail.rawValue, legacySidebarValue: return .rail
        default: return .tabs
        }
    }

    static func style(_ defaults: UserDefaults = .standard) -> Style {
        style(raw: defaults.string(forKey: styleKey))
    }

    static func isRail(_ defaults: UserDefaults = .standard) -> Bool {
        style(defaults) == .rail
    }

    /// "browsing" reads as Hide While Browsing, "hidden" as Hidden (FEAT-62); anything else is
    /// Always Visible (the default).
    static func railVisibility(raw: String?) -> RailVisibility {
        guard let raw else { return .always }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case RailVisibility.whileBrowsing.rawValue: return .whileBrowsing
        case RailVisibility.hidden.rawValue: return .hidden
        default: return .always
        }
    }

    static func railVisibility(_ defaults: UserDefaults = .standard) -> RailVisibility {
        railVisibility(raw: defaults.string(forKey: railVisibilityKey))
    }

    /// Rail mode with the rail Always Visible in Centre: the only configuration that moves content.
    /// FEAT-80: Corner reserves nothing, as at rest it is only the Home icon in the corner (the
    /// device pass checks that no page's top-left header sits under it).
    static func reservesWidth(_ defaults: UserDefaults = .standard) -> Bool {
        isRail(defaults) && reservesWidth(visibility: railVisibility(defaults), position: railPosition(defaults))
    }

    /// The pure half of `reservesWidth(_:)`, Rail mode assumed.
    static func reservesWidth(visibility: RailVisibility, position: RailPosition) -> Bool {
        visibility == .always && position == .centre
    }

    // MARK: Migration (P4 R6, §4.2)

    /// What a PERSISTED `sidebar_style` value migrates to: "rail" for exactly FEAT-30's "sidebar",
    /// nil (leave it alone) for everything else, including a missing key and "rail" itself.
    static func migratedValue(forPersisted raw: Any?) -> String? {
        guard let value = raw as? String, value == legacySidebarValue else { return nil }
        return Style.rail.rawValue
    }

    /// Once per launch from `NuvioTVApp.init`, before any view reads the mode. Reads the PERSISTENT
    /// domain only (`persistentDomain(forName: domain)`), so a `-sidebar_style sidebar` launch
    /// argument, which lives in the argument domain, is never written to disk. Idempotent: it writes
    /// only while the stored value is exactly "sidebar", so a second run is a no-op. Never touches
    /// `rail_visibility`, which an untouched install leaves unset (Always Visible). Returns whether
    /// it wrote.
    @discardableResult
    static func migrateLegacy(_ defaults: UserDefaults, domain: String) -> Bool {
        guard !domain.isEmpty,
              let migrated = migratedValue(forPersisted: defaults.persistentDomain(forName: domain)?[styleKey])
        else { return false }
        defaults.set(migrated, forKey: styleKey)
        NSLog("[NavRail] migrated %@ \"%@\" to \"%@\" (device-local, once)", styleKey, legacySidebarValue, migrated)
        return true
    }

    // MARK: Inset math (P4 R3, §5.1)

    /// How much leading safe area an Always Visible rail adds to every tab root: the reserved edge
    /// beyond the side safe area the content already keeps (116 − 80 = 36 on a 1080p canvas). Never
    /// negative, and 0 when the rail does not reserve width or (FEAT-80) sits in the Corner.
    static func contentSafeAreaExtra(sideSafeArea: CGFloat, reservesWidth: Bool, position: RailPosition) -> CGFloat {
        guard reservesWidth, position == .centre else { return 0 }
        return max(0, reservedEdge - sideSafeArea)
    }

    /// Where a tab root's content starts from the bezel: the side safe area, the rail's extra, then
    /// the 60 pt content margin (`Theme.Spacing.screen`). 176 Always Visible in Centre, 140 otherwise.
    static func contentLeading(sideSafeArea: CGFloat, reservesWidth: Bool, position: RailPosition) -> CGFloat {
        sideSafeArea + contentSafeAreaExtra(sideSafeArea: sideSafeArea, reservesWidth: reservesWidth, position: position)
            + Theme.Spacing.screen
    }

    /// The rows' distance to the visible screen edges (`\.rowEdgeMargins`), the rail's edge counting
    /// as the leading one: (176, 140) Always Visible in Centre, (140, 140) otherwise (Corner included,
    /// FEAT-80). Computed from the passed side safe area, so production (which passes
    /// `PinnedRowGeometry.sideSafeArea`) gets exactly `RowEdgeMargins.standard` when the rail
    /// reserves nothing.
    static func rowEdgeMargins(sideSafeArea: CGFloat, reservesWidth: Bool, position: RailPosition) -> RowEdgeMargins {
        let margin = Theme.Spacing.screen + sideSafeArea
        return RowEdgeMargins(
            leading: margin + contentSafeAreaExtra(sideSafeArea: sideSafeArea, reservesWidth: reservesWidth,
                                                   position: position),
            trailing: margin
        )
    }

    /// See `Theme.Size.sidebarTopCompensation` (still ships 0, so `.railTopCompensation()` applies
    /// nothing). Main-actor: the constant lives with the pinned-hero budget in `Theme.Size`.
    @MainActor
    static var topCompensation: CGFloat { Theme.Size.sidebarTopCompensation }
}

// MARK: - Rail focus policy (P4 §2)

/// Why the rail opened. Decides what Menu does inside it (`RailFocusPolicy.menuInRail`).
nonisolated enum RailOpenReason: String, Equatable, Sendable {
    /// A Left the focus engine could not place, from the leftmost item of a tab's content.
    case left
    /// Menu at a tab root (or at Stage's row 0).
    case menu
    /// Focus landed on the hidden system tab bar (tvOS's search field does this on Menu, S1 W2).
    case hiddenBarRedirect
    /// A hand-off to content found nothing to focus, so the rail took focus back.
    case rearm
}

/// The rail's focus decisions as pure functions of plain facts (P4 §2.2–§2.4).
nonisolated enum RailFocusPolicy {
    /// A failed move (`UIFocusSystem.movementDidFailNotification`) opens the rail only when every
    /// condition holds: a plain Left (never a diagonal with Up or Down), Rail mode, the rail not
    /// already holding (or taking) focus, the failed move starting inside a tab's content (never the
    /// hidden bar, never the rail itself), nothing presented over the shell (player, stream picker,
    /// trailer cover, alerts) and no app-handled Left owning the press (Classic's hero carousel).
    static func shouldArm(heading: UIFocusHeading,
                          railMode: Bool,
                          railHoldsFocus: Bool,
                          originInTabContent: Bool,
                          presentedOverShell: Bool,
                          vetoed: Bool) -> Bool {
        heading.contains(.left)
            && heading.isDisjoint(with: [.up, .down])
            && railMode
            && !railHoldsFocus
            && originInTabContent
            && !presentedOverShell
            && !vetoed
    }

    enum InRailMove: Equatable, Sendable {
        /// Right: leave the rail for the tab on screen (P4 R1).
        case exitToContent
        /// Up past the top item, Down past the bottom one, Left: nothing happens.
        case contained
    }

    /// A move the engine could not place while the rail holds focus. Content is gated then, so
    /// Right always fails, and the rail turns it into its exit.
    static func moveFailedInRail(heading: UIFocusHeading) -> InRailMove {
        heading.contains(.right) ? .exitToContent : .contained
    }

    enum MenuInRail: Equatable, Sendable {
        /// Close the rail back to the content it opened from.
        case closeToContent
        /// No handler: the system default, which from a tab shell suspends the app.
        case systemDefault
    }

    /// P4 R4 (critique Q2, decided 2026-10-05): Menu closes a rail that Left opened; in a rail that
    /// Menu (or the hidden-bar redirect, or a re-arm) opened it is the system default, so Menu
    /// opens the rail at a tab root and Menu again leaves the app, the remote's normal grammar.
    static func menuInRail(openedBy reason: RailOpenReason) -> MenuInRail {
        reason == .left ? .closeToContent : .systemDefault
    }

    enum SelectAction: Equatable, Sendable {
        case switchTab(Int)
        case returnToCurrent
    }

    /// P4 R1: Select switches to another tab; Select on the current tab's item is the same as Right.
    static func select(item: Int, currentTab: Int) -> SelectAction {
        item == currentTab ? .returnToCurrent : .switchTab(item)
    }
}

// MARK: - Rail visibility (P4 §1.1, §5.2)

/// Whether the pill is on screen, in precedence order. Focus wins over every hide term: removing a
/// view that holds focus is the BUG-47 class (focus falls to whatever is left and the next Menu
/// exits the app).
nonisolated enum RailVisibilityRule {
    struct Inputs: Equatable, Sendable {
        var railMode: Bool
        /// A rail item holds focus.
        var holdsFocus: Bool
        /// A Menu, Left or redirect opened the rail and focus has not left it since.
        var revealed: Bool
        /// The app-root deep-link cover (Top Shelf) is up.
        var rootCoverActive: Bool
        /// An immersive screen (Detail) is pushed.
        var immersive: Bool
        /// The current tab's settled "scrolled down" mirror.
        var scrolledDown: Bool
        var visibility: NavigationChrome.RailVisibility
        var selectedTab: Int
        /// Search & Discover B4: focus is inside tvOS's system search keyboard
        /// (`NavigationChromeModel.searchKeyboardFocused`). Last, with a default, so existing call
        /// sites compile unchanged.
        var keyboardFocused: Bool = false
    }

    /// The Search tab's selection value: Hide While Browsing keeps the rail off its keyboard (R7).
    static let searchTab = 1

    /// `!railMode` → hidden; holds focus → shown; root cover → hidden; revealed → shown; Always
    /// Visible → shown, except on Search while its keyboard holds focus (B4); Hidden (FEAT-62) →
    /// hidden (only the focus and reveal terms above ever show it); then (Hide While Browsing, R7)
    /// immersive → hidden; Search → hidden; scrolled down → hidden; otherwise shown.
    static func shown(_ i: Inputs) -> Bool {
        guard i.railMode else { return false }
        if i.holdsFocus { return true }
        if i.rootCoverActive { return false }
        if i.revealed { return true }
        if i.visibility == .always { return !keyboardHidesRail(selectedTab: i.selectedTab, keyboardFocused: i.keyboardFocused) }
        if i.visibility == .hidden { return false }
        if i.immersive { return false }
        if i.selectedTab == searchTab { return false }
        if i.scrolledDown { return false }
        return true
    }

    /// B4: Search's keyboard holds focus. Hides the Always Visible pill and (unless the
    /// `-debug.railSearchInsetHold` A/B knob holds it) collapses the reserved leading inset.
    static func keyboardHidesRail(selectedTab: Int, keyboardFocused: Bool) -> Bool {
        keyboardFocused && selectedTab == searchTab
    }

    /// B4: the shell's reserved leading safe area. Always Visible's extra (36 pt on a standard
    /// screen), 0 while Search's keyboard holds focus unless `holdInset` (the A/B knob). Hide While
    /// Browsing and Hidden (FEAT-62) never reserve width: 0. Neither does Corner (FEAT-80), in any
    /// visibility.
    static func reservedLeadingInset(sideSafeArea: CGFloat,
                                     visibility: NavigationChrome.RailVisibility,
                                     position: NavigationChrome.RailPosition,
                                     selectedTab: Int,
                                     keyboardFocused: Bool,
                                     holdInset: Bool) -> CGFloat {
        guard NavigationChrome.reservesWidth(visibility: visibility, position: position) else { return 0 }
        if !holdInset, keyboardHidesRail(selectedTab: selectedTab, keyboardFocused: keyboardFocused) { return 0 }
        return NavigationChrome.contentSafeAreaExtra(sideSafeArea: sideSafeArea, reservesWidth: true, position: position)
    }
}

/// B4's A/B knob: `-debug.railSearchInsetHold YES` keeps Always Visible's reserved inset while the
/// Search keyboard holds focus, so only the pill hides (animating the inset re-lays out the search
/// container and shifts the Grid keyboard 36 pt). Read in DEBUG and Release, latched at launch.
nonisolated enum RailSearchInsetHold {
    static let defaultsKey = "debug.railSearchInsetHold"
    static let current: Bool = UserDefaults.standard.bool(forKey: defaultsKey)
}

/// How a scrolled-down write should move the rail (P4 §1.3, #8). Recorded per tab with the write.
nonisolated enum RailMotion: Equatable, Sendable {
    /// A scroll mirror crossing: the hide edge is immediate, the show edge waits the resting settle.
    case scroll
    /// Stage's strip starting a page: both edges move with the page's own curve and duration, and
    /// no settle (the row index is discrete).
    case page(seconds: TimeInterval)
}

/// A reveal request: a counter, so two Menu presses in a row are two observable changes, plus why.
nonisolated struct RailRevealRequest: Equatable, Sendable {
    var generation: Int
    var reason: RailOpenReason
}

// MARK: - Content gate mode (DEBUG A/B)

/// How the rail makes tab content unfocusable while it holds focus (P4 R2, §2.3). The Wave 0.5
/// spike found the engine otherwise leaks out of the overlay: Down past the bottom item into
/// content, and Right from row 1 to an off-screen row-0 card.
///
///  - `uikit` (the primary): one `isUserInteractionEnabled = false` on the tab controller's view.
///    Covers every tab root, every pushed page and the UIKit-hosted Search keyboard at one site,
///    with no SwiftUI invalidation. Unproven for SwiftUI focus items (Risk 1); Probe G decides.
///  - `perTab` (the specified fallback): `.disabled` on each tab root from the shell-level gate, the
///    spike's device-proven mechanism. May leave the Search keyboard ungated (Q5).
///
/// `-debug.railGate uikit|perTab` picks one for the main session's simulator A/B. DEBUG builds only;
/// Release always runs the primary. Launch-latched: `.railTabRoot` branches on it structurally.
nonisolated enum RailGateMode: String, Equatable, Sendable {
    case uikit
    case perTab

    static let defaultsKey = "debug.railGate"

    /// "perTab" (any case, or "per-tab") picks the fallback; anything else is the primary.
    static func resolve(_ raw: String?) -> RailGateMode {
        guard let raw else { return .uikit }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pertab", "per-tab": return .perTab
        default: return .uikit
        }
    }

    static let current: RailGateMode = {
        #if DEBUG
        return resolve(UserDefaults.standard.string(forKey: defaultsKey))
        #else
        return .uikit
        #endif
    }()
}
