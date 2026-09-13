import Combine
import SwiftUI

/// Immersive content and trailer coverage for the tab shell. Only TabBarPresentation controls
/// native tab visibility; individual tabs must not install competing toolbar preferences.
/// An environment default keeps standalone detail/deep-link presentations independent.
@MainActor
final class TabBarVisibility: ObservableObject {
    private var immersiveOwners: Set<UUID> = []
    private var detailDepth: Int { immersiveOwners.count }

    /// View identity makes repeated lifecycle callbacks idempotent. Coalescing in the shell
    /// also prevents a parent disappear/child appear from flashing the bar between details.
    func pushImmersive(owner: UUID) {
        guard immersiveOwners.insert(owner).inserted else { return }
        recompute()
    }

    func popImmersive(owner: UUID) {
        guard immersiveOwners.remove(owner) != nil else { return }
        recompute()
        TabBarProbe.recordPop(depthAfter: detailDepth)
    }

    /// BUG-30/66/62 diagnostics only — read-only surface of the depth `immersiveHidden` is
    /// computed from, for the About pane's live tab-bar readout.
    var immersiveDepth: Int { detailDepth }

    /// FEAT-25 (device pass 2026-08-21): whether the HOME tab's root content is the frontmost
    /// surface — false while another tab is selected or an immersive screen is pushed over it.
    /// Exists because neither event fires `onDisappear` on Home's subtree (each tab keeps its
    /// NavigationStack alive across a switch, and a push keeps the stack root mounted), so the
    /// hero's autoplaying trailer kept making sound under Detail pages and in Settings. Published
    /// so `HomeHeroBackdrop` can subscribe imperatively (`onReceive`) — the covered subtree is
    /// still hierarchy-resident (that's the bug) but may not re-render while hidden, so a
    /// render-driven gate could defer teardown exactly when it matters.
    @Published private(set) var homeSurfaceCovered = false
    @Published private(set) var browseSurfaceCovered = true
    private var browseTabSelected = false
    private var searchResultsActive = false

    /// Search retains its discovery surface for scroll restoration, but its trailer must stop.
    func setSearchResultsActive(_ active: Bool) {
        guard searchResultsActive != active else { return }
        searchResultsActive = active
        recomputeHomeCovered()
    }

    func setBrowseTabSelected(_ selected: Bool) {
        guard browseTabSelected != selected else { return }
        browseTabSelected = selected
        recomputeHomeCovered()
    }

    private var homeTabSelected = true {
        didSet { recomputeHomeCovered() }
    }
    /// ContentView's app-root deep-link cover (Top Shelf) — presented over the whole shell, so
    /// it covers Home without touching tab selection or push depth (Codex beta.14 r8).
    private var rootCoverActive = false {
        didSet { recomputeHomeCovered() }
    }

    /// MainTabView reports selection changes here (Home is tab value 0).
    func setHomeTabSelected(_ selected: Bool) {
        guard homeTabSelected != selected else { return }
        homeTabSelected = selected
    }

    /// MainTabView forwards ContentView's deep-link cover presence here.
    func setRootCoverActive(_ active: Bool) {
        guard rootCoverActive != active else { return }
        rootCoverActive = active
    }

    private func recomputeHomeCovered() {
        let covered = !homeTabSelected || detailDepth > 0 || rootCoverActive
        if homeSurfaceCovered != covered { homeSurfaceCovered = covered }
        let browseCovered = !browseTabSelected || searchResultsActive || detailDepth > 0 || rootCoverActive
        if browseSurfaceCovered != browseCovered { browseSurfaceCovered = browseCovered }
    }

    /// T3: also drives `immersiveHidden` now — see that property's doc comment for why the write
    /// is guarded to an actual 0↔>0 crossing rather than reassigning on every `detailDepth`
    /// change.
    private func recompute() {
        let hidden = detailDepth > 0
        if immersiveHidden != hidden { immersiveHidden = hidden }
        recomputeHomeCovered()
    }

    /// Only publish actual visibility changes. The presentation coordinator coalesces lifecycle
    /// updates and restores the bar after the navigation transition has completed.
    @Published private(set) var immersiveHidden: Bool = false
}

private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue = TabBarVisibility()
}

extension EnvironmentValues {
    var tabBarVisibility: TabBarVisibility {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

/// One `.onScrollGeometryChange` sample, carried as a small `Equatable` struct rather than a
/// single pre-combined `CGFloat`. Two reasons: the BUG-30/66/62 diagnostics pane needs `y` and
/// `i` separately to be interpretable (see `TabBarProbe.ScrollState`), and observing the inset
/// (not just the offset) means this callback also fires on the system bar's own minimize/expand
/// transitions — timestamping exactly the BUG-66 moment the bar's resolved visibility changes.
/// Hysteresis is unaffected by those extra fires: `residual` is inset-invariant at rest, so a
/// same-position re-fire from a bar transition never crosses either arm on its own.
private struct TabBarScrollSample: Equatable {
    var offsetY: CGFloat
    var insetTop: CGFloat
    /// T1 sign fix: 0 at a scroll view's true top, matching the in-tree formula this residual
    /// was always supposed to share (`HomeView.swift`'s probe, ~L1276: `contentOffset.y +
    /// contentInsets.top`). The OLD formula here (`offset.y - insets.top`) was a sign error —
    /// at the true top `contentOffset.y == -contentInsets.top`, so the old expression evaluated
    /// to −2×insetTop instead of 0, and every threshold below it was tuned against that wrong
    /// number.
    var residual: CGFloat { offsetY + insetTop }
}

/// Reports a tab root's main scroll view position via hysteresis so the bar doesn't flicker right
/// at one boundary. `hidesBar` mirrors the last state actually reported, so `isScrolledDown` only
/// changes on a real crossing — not once per scroll tick.
///
/// T2: this used to also forward crossings to the shared `TabBarVisibility` via `setScrolled(_:)`
/// — retired along with that method (see the class doc comment): a single shared slot fed by
/// whichever tab last fired is wrong when four tabs scroll independently, and nothing besides
/// `isScrolledDown` ever needed the crossing anyway. This modifier is now purely local per-tab
/// state.
private struct TabBarScrollAutoHide: ViewModifier {
    @State private var hidesBar = false
    /// FEAT-30: the sidebar's own copy of this hysteresis, so the floating panel can get out of
    /// the way while the user browses rows. Read through `@Environment` (no observation), and
    /// written only on the same crossings the local latch flips on — never per scroll tick.
    @Environment(\.sidebarChrome) private var sidebarChrome
    /// BUG-30/66/62: which tab root this is, for the About-pane diagnostics readout.
    let tab: String
    /// Optional mirror of `hidesBar` for the attaching screen's own use (BUG-27: Home keys its
    /// Menu-to-top shortcut off the same hysteresis the bar uses, so the two never disagree).
    var isScrolledDown: Binding<Bool>?

    /// T1: hysteresis arms restated in the corrected (sign-fixed) residual frame. Under the OLD
    /// mis-signed `offset.y - insets.top` formula, the literal thresholds (60 / 8) worked out to
    /// EFFECTIVE arms that were inset-dependent — the same literals meant different things
    /// depending on whether the system bar was expanded or minimized at the moment of the fire:
    ///   expanded bar (insetTop≈157): hide fired past residual>374, show fired below residual<322
    ///   minimized bar (insetTop≈76):  hide fired past residual>212, show fired below residual<160
    /// (derived by adding 2×insetTop to each old literal — the sign error's exact offset).
    /// `hideArm` = 300 sits between the two historical hide points, so it engages after roughly
    /// one row scrolled — the same felt behavior as today. `showArm` = 160 is the historical
    /// MINIMIZED-bar show point, chosen over the expanded-bar one because it is also comfortably
    /// above both the documented 59–67pt rest-short-of-top (HomeView.swift ~L794-806, BUG-30) and
    /// the pinned hero's headroom — LOAD-BEARING: if the show arm sat below that rest-short
    /// residual, `isScrolledDown` would stay latched even at the visual top, and BUG-27's
    /// Menu-to-top handler (HomeView.swift ~L559-608) would never disarm — Menu could never exit
    /// the app from Home. If a device pass finds 160 too eager, the conservative fallback pair is
    /// the expanded-bar values above (374 / 322), which reproduce today's shipped behavior
    /// byte-for-byte.
    private static let hideArm: CGFloat = 300
    private static let showArm: CGFloat = 160

    /// FEAT-30: tab NAME → `TabView` selection value, so the sidebar can key its per-tab
    /// scrolled-down map by the same number `selectedTab` carries. A table here rather than a new
    /// parameter on `reportsScrollToTabBar` — the four call sites (Home, Search, Library, Add-ons)
    /// keep their existing `tab:` signature, and the names they already pass are the same ones
    /// `TabBarProbe.tabNames` fixes for the diagnostics readout. Settings and Profile never attach
    /// this modifier (they don't meaningfully scroll), so they are correctly absent.
    private static let tabIndexByName: [String: Int] = ["Home": 0, "Search": 1, "Library": 2, "Add-ons": 3, "Live TV": 6, "Browse": 1]

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: TabBarScrollSample.self, of: { geo in
            TabBarScrollSample(offsetY: geo.contentOffset.y, insetTop: geo.contentInsets.top)
        }, action: { _, sample in
            TabBarProbe.recordScrollFire(tab: tab, offsetY: sample.offsetY, insetTop: sample.insetTop)
            let residual = sample.residual
            if !hidesBar, residual > Self.hideArm {
                hidesBar = true
                isScrolledDown?.wrappedValue = true
                reportToSidebar(true)
            } else if hidesBar, residual < Self.showArm {
                hidesBar = false
                isScrolledDown?.wrappedValue = false
                reportToSidebar(false)
            }
        })
    }

    /// Gated on the mode, not just on whether anything is listening: in tabs mode this must not
    /// even touch the shared model, so the default (unconnected) instance every non-shell screen
    /// falls back to stays untouched too. One `UserDefaults` read per CROSSING — the hysteresis
    /// above is what makes that a handful of reads per page walk rather than one per frame.
    private func reportToSidebar(_ scrolledDown: Bool) {
        guard SidebarChrome.isEnabled(), let index = Self.tabIndexByName[tab] else { return }
        sidebarChrome.setScrolledDown(tab: index, scrolledDown)
    }
}

extension View {
    /// Attach to a tab root's main (vertical) `ScrollView` so its position drives the floating tab
    /// bar's scroll-driven auto-hide. Screens that don't meaningfully scroll (Settings, Profile)
    /// should not attach this. `tab` names the tab root for the BUG-30/66/62 diagnostics readout
    /// (e.g. "Home", "Search"). Pass `isScrolledDown` to also receive the same hysteresis-filtered
    /// signal locally (crossings only, never per scroll tick).
    func reportsScrollToTabBar(tab: String, isScrolledDown: Binding<Bool>? = nil) -> some View {
        modifier(TabBarScrollAutoHide(tab: tab, isScrolledDown: isScrolledDown))
    }
}

/// BUG-30/66/62 (beta.14): release-safe diagnostics for the tvOS 26 system tab bar's scroll-edge
/// state. Same house pattern as `HomeHeroProbe` (deliberately not `#if DEBUG` — this bar has only
/// ever been seen stuck on a device pass, never in sim) but the readout is a live counter
/// snapshot rather than an event log: `.onScrollGeometryChange` can fire many times a second while
/// scrolling, and a line per fire would spam both the console and whatever ring buffer held it.
/// Everything here is in-memory only for the running process — the BUG-30/66 protocol (walk Home
/// down/up, then run Detail push/pop cycles, then check Settings → About) never spans a
/// relaunch — so nothing here touches UserDefaults or feeds back into the bar's own state.
@MainActor
enum TabBarProbe {
    /// Live read, not the other probes' latched `static let`: those pair with a relaunch-based
    /// capture protocol, while this toggle must take effect in the same session it is flipped in.
    nonisolated static var enabled: Bool { UserDefaults.standard.bool(forKey: "debug.tabBarProbe") }

    /// Stable display order for the About pane — dictionary iteration order isn't.
    static let tabNames = ["Home", "Search", "Library", "Add-ons"]

    struct ScrollState {
        var fireCount = 0
        var lastFireMs = 0
        /// T1: `y`/`i` kept separate (not just the combined residual) so the About-pane readout
        /// can show all three — a tester's photo of `y=… i=… r=…` is what lets a device pass
        /// distinguish "the bar never fired" from "it fired but the residual math is wrong".
        var lastOffsetY: CGFloat = 0
        var lastInsetTop: CGFloat = 0
        var lastResidual: CGFloat = 0
    }

    private(set) static var scrollStates: [String: ScrollState] = [:]
    /// Counts full push→pop round trips (depth back to 0), not raw push/pop calls — the BUG-30/66
    /// hypothesis is stated in terms of "N push/pop cycles", not a raw event tally.
    private(set) static var pushPopCycles = 0

    static func recordScrollFire(tab: String, offsetY: CGFloat, insetTop: CGFloat) {
        guard enabled else { return }
        var state = scrollStates[tab, default: ScrollState()]
        state.fireCount += 1
        state.lastFireMs = HomeHeroProbe.sinceLaunchMs
        state.lastOffsetY = offsetY
        state.lastInsetTop = insetTop
        state.lastResidual = offsetY + insetTop
        scrollStates[tab] = state
    }

    static func recordPop(depthAfter: Int) {
        guard enabled, depthAfter == 0 else { return }
        pushPopCycles += 1
    }
}
