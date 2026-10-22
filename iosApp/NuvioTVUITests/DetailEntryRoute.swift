import XCTest

/// The Detail legs' one route into a Detail page that does not depend on the fixture's Home content
/// (`DetailActionSquareUITests`, `DetailFocusReturnUITests`).
///
/// 2026-10-22: the old route ("up ×6, down ×1, Select" from Classic Home) started landing on an
/// entry of the FA87 fixture's Home that opens the PLAYER (a Ted Lasso scene) once that Home's
/// content changed, so `DetailActionSquareUITests` failed with "Play button never appeared on
/// Detail" and the `DetailFocusReturnUITests` Back legs skipped. The route now goes through Search:
///
///   profile picker ("Chris" focused, read) → tab bar or rail → Search (focused, read)
///   → inline keyboard (a key focused, read) → type the query → wait for the Top result
///   → Down until the Top result card holds focus and names the query (read) → Select
///   → wait for `detail_action_play`.
///
/// Without a Top result (Search Results set to per-add-on rows) the first row card that names the
/// query stands in for it, found the same way. A query with no results moves on to the next one.
///
/// SAFETY (a blind Select on this fixture once created real profiles on the account): every Select
/// here follows a focus read (`hasFocus`; FA87's tvOS 26.5 runtime reports it). When focus cannot
/// be verified the route records a failure and returns WITHOUT pressing. It never presses Play,
/// never selects a suggestion chip, never long-presses and never writes a setting.
///
/// Fallback: the old Home-hero route survives only in a verified form. It runs only when the Search
/// route gave up BEFORE any content Select, and presses Select only when the element focused one
/// Down under the tab bar is the Home hero's CTA ("Go to Movie: …" / "Go to Show: …", a
/// NavigationLink to Detail, never to playback; "Open Folder" is not taken). Anything else fails.
///
/// Launch: every launch adds `-debug.rememberLastProfile NO` (the DEBUG override of "Open Last
/// Profile at Launch", in memory only, never persisted) so the picker always shows and the "Chris"
/// check runs on every launch.
///
/// Shared rather than copied per file (the harness's usual convention) because both Detail files
/// must take the same route; the target's synchronized group picks the file up.
struct DetailEntryRoute {

    enum Outcome {
        case opened
        /// Gave up before any content Select (focus is somewhere harmless): the fallback may run.
        case unavailable(String)
        /// A content Select was pressed and no Detail page followed: no fallback.
        case failed(String)
    }

    let test: XCTestCase
    let app: XCUIApplication
    private let remote = XCUIRemote.shared

    /// The series the FA87 fixture's add-ons find first, then a film.
    static let defaultQueries = ["Severance", "Dune"]

    /// The system tab bar's titles (Search & Discover: Discover is its own tab by default).
    private static let tabTitles = ["Home", "Search", "Discover", "Library", "Add-ons", "Settings", "Profile"]

    /// The rail's `focused=` ids for the two items this route opens (`RailItem` selection order).
    private static let railIDs = ["Home": 0, "Search": 1]

    // MARK: - Entry point

    /// Launches with `arguments` (plus `-debug.rememberLastProfile NO`), enters "Chris" and opens a
    /// Detail page by Search (fallback: the verified hero CTA). On success `detail_action_play`
    /// exists; on any unverified focus it records a failure and returns without pressing.
    @discardableResult
    static func launchToDetail(_ test: XCTestCase, arguments: [String],
                               queries: [String] = defaultQueries) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments + ["-debug.rememberLastProfile", "NO"]
        app.launch()
        let route = DetailEntryRoute(test: test, app: app)
        guard route.enterChrisProfile() else { return app }
        route.openDetail(queries: queries)
        return app
    }

    /// From anywhere past the profile picker: Search first, the verified hero CTA second.
    @discardableResult
    func openDetail(queries: [String] = defaultQueries) -> Bool {
        switch openViaSearch(queries: queries) {
        case .opened:
            return true
        case .failed(let reason):
            shot("detail_route_failed")
            XCTFail("Detail route (Search): \(reason)")
            return false
        case .unavailable(let reason):
            note("detail_route_search_unavailable", reason)
            switch openViaHomeHero() {
            case .opened:
                return true
            case .unavailable(let why), .failed(let why):
                shot("detail_route_failed")
                XCTFail("Detail route: Search unavailable (\(reason)); hero fallback: \(why)")
                return false
            }
        }
    }

    // MARK: - Profile picker

    /// Selects the "Chris" tile only once it reads focused (Left, then Right, one press at a time).
    func enterChrisProfile() -> Bool {
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        guard chris.waitForExistence(timeout: 90) else {
            XCTFail("profile picker never appeared — is the sim session still signed in?")
            return false
        }
        pause(1)
        guard moveFocus(.left, until: chris, max: 4) || moveFocus(.right, until: chris, max: 6) else {
            shot("detail_route_profile_unverified")
            XCTFail("the \"Chris\" tile never read focused on the profile picker (focused: \(focusedLabels())) — not pressing Select")
            return false
        }
        note("detail_route_profile", "Select on '\(chris.label)' (hasFocus)")
        remote.press(.select)
        let home = app.buttons["Home"]
        let rail = app.descendants(matching: .any)["rail_state"].firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !home.exists, !rail.exists { pause(0.5) }
        pause(8) // add-on manifests + catalog fan-out (Search reads the same add-ons)
        return true
    }

    // MARK: - Search route

    private func openViaSearch(queries: [String]) -> Outcome {
        guard openTab("Search") else {
            return .unavailable("could not put verified focus on the Search tab (focused: \(focusedLabels()))")
        }
        guard app.searchFields.firstMatch.waitForExistence(timeout: 10) else {
            return .unavailable("Search showed no search field")
        }
        for query in queries {
            guard focusSearchKeyboard() else {
                return .unavailable("no key of the inline keyboard took focus (focused: \(focusedLabels()))")
            }
            let current = searchFieldText()
            if !current.isEmpty {
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
                pause(1)
            }
            app.typeText(query)
            pause(1)
            let typed = searchFieldText()
            guard typed.caseInsensitiveCompare(query) == .orderedSame else {
                note("detail_route_typed_\(query)", "typed '\(query)', the field reads '\(typed)'")
                continue
            }
            guard let hasTopResult = waitForResults() else {
                note("detail_route_no_results_\(query)", "no results for '\(query)': \(searchState())")
                continue
            }
            shot("detail_route_results_\(query)")
            guard let label = focusResultCard(query: query, topResult: hasTopResult) else {
                return .unavailable("focus never verifiably reached a result card naming '\(query)' "
                    + "(topResult=\(hasTopResult), focused: \(focusedLabels()))")
            }
            note("detail_route_select", "Select on the focused result '\(label)' (query '\(query)')")
            remote.press(.select)
            if waitForDetail() { return .opened }
            return .failed("no detail_action_play 30 s after selecting '\(label)' "
                + "(keyboards=\(app.keyboards.count), focused: \(focusedLabels()))")
        }
        return .unavailable("no query produced a typed field and results: \(queries)")
    }

    /// Waits up to 20 s: true once the Top result is up, false when only result rows are (per-add-on
    /// mode), nil when nothing came back (or "No results for …" settled).
    private func waitForResults() -> Bool? {
        let top = app.descendants(matching: .any)["search.topResult"].firstMatch
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search.group.'")).firstMatch
        let noResults = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No results for")).firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if top.exists { pause(1.5); return true }
            if noResults.exists { return nil }
            pause(0.5)
        }
        if top.exists { return true }
        return rows.exists ? false : nil
    }

    /// Moves focus from the keyboard to the Top result card (or, with no Top result, to the first
    /// row card naming `query`), reading focus after every press. Returns the focused card's label,
    /// or nil when the target never verifiably held focus (nothing is pressed then).
    private func focusResultCard(query: String, topResult: Bool) -> String? {
        // Keyboard → suggestion chips → Top result → (People) → rows: Down, Up on overshoot.
        for _ in 0..<6 {
            let spot = focusedSearchSpot()
            if topResult, spot.container == "search.topResult" { break }
            if !topResult, spot.container?.hasPrefix("search.group.") == true { break }
            let pastTop = spot.container == "search.people" || spot.container?.hasPrefix("search.group.") == true
            remote.press(topResult && pastTop ? .up : .down)
            pause(0.9)
        }
        let spot = focusedSearchSpot()
        if topResult {
            guard spot.container == "search.topResult" else { return nil }
            return names(spot.label, query) ? spot.label : nil
        }
        guard let row = spot.container, row.hasPrefix("search.group.") else { return nil }
        for _ in 0..<6 {
            remote.press(.left)
            pause(0.4)
        }
        for _ in 0..<10 {
            let card = focusedSearchSpot()
            guard card.container == row else { return nil }
            if names(card.label, query) { return card.label }
            remote.press(.right)
            pause(0.6)
        }
        return nil
    }

    private func names(_ label: String, _ query: String) -> Bool {
        label.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The deepest focused element and the Search container it sits in (`search.topResult`,
    /// `search.group.*`, `search.people`, `search.suggestions`; nil elsewhere), from ONE snapshot.
    private func focusedSearchSpot() -> (container: String?, label: String) {
        guard let root = try? app.snapshot() else { return (nil, "") }
        var hits: [(container: String?, label: String)] = []
        func walk(_ node: XCUIElementSnapshot, _ container: String?) {
            let id = node.identifier
            let isContainer = id == "search.topResult" || id == "search.people" || id == "search.suggestions"
                || id.hasPrefix("search.group.")
            let here = isContainer ? id : container
            if node.hasFocus { hits.append((here, node.label)) }
            node.children.forEach { walk($0, here) }
        }
        walk(root, nil)
        return hits.last(where: { !$0.label.isEmpty }) ?? hits.last ?? (nil, "")
    }

    /// Puts focus on a key of the inline search keyboard: Down from the tab bar, Right from the
    /// rail, Up (linear) / Left (grid) from content below it. True only once a key reads focused.
    private func focusSearchKeyboard() -> Bool {
        guard app.keyboards.firstMatch.waitForExistence(timeout: 8) else { return false }
        for _ in 0..<5 {
            if keyboardHasFocus() { return true }
            if railMode(), railFocusedItem() >= 0 {
                remote.press(.right)
            } else if focusedTab() != nil {
                remote.press(.down)
            } else {
                remote.press(keyboardIsGrid() ? .left : .up)
            }
            pause(0.7)
        }
        return keyboardHasFocus()
    }

    private func keyboardHasFocus() -> Bool {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists, let root = try? keyboard.snapshot() else { return false }
        func walk(_ node: XCUIElementSnapshot) -> Bool { node.hasFocus || node.children.contains(where: walk) }
        return walk(root)
    }

    /// Linear keyboard ≈ 1760 wide (FA87), grid under 900.
    private func keyboardIsGrid() -> Bool {
        app.keyboards.firstMatch.exists && app.keyboards.firstMatch.frame.width < 900
    }

    /// The field's text without the prompt or the ", Press … to change keyboards" hint.
    private func searchFieldText() -> String {
        var value = (app.searchFields.firstMatch.value as? String) ?? ""
        if let hint = value.range(of: ", Press ") { value = String(value[..<hint.lowerBound]) }
        return value == "Search movies & shows" ? "" : value
    }

    private func searchState() -> String {
        let probe = app.descendants(matching: .any)["search_state"].firstMatch
        return probe.exists ? probe.label : "search_state absent"
    }

    // MARK: - Verified Home-hero fallback

    private func openViaHomeHero() -> Outcome {
        guard openTab("Home") else {
            return .unavailable("could not put verified focus on the Home tab (focused: \(focusedLabels()))")
        }
        pause(2)
        if !railMode() {
            remote.press(.down) // tab bar → the first focusable thing under it
            pause(1.2)
        }
        let focused = focusedLabels()
        guard let cta = focused.last(where: { $0.hasPrefix("Go to Movie:") || $0.hasPrefix("Go to Show:") }) else {
            return .unavailable("focus under the tab bar is not the hero's Go to Movie/Show CTA (focused: \(focused)) — not pressing Select")
        }
        note("detail_route_hero_select", "fallback: Select on the focused hero CTA '\(cta)'")
        remote.press(.select)
        return waitForDetail() ? .opened : .failed("no detail_action_play 30 s after selecting the hero CTA '\(cta)'")
    }

    // MARK: - Tabs and rail

    /// Opens a tab, pressing Select only while that tab (or rail item) reads focused.
    private func openTab(_ title: String) -> Bool {
        if railMode() { return openRailItem(title) }
        guard climbToTabBar() else { return false }
        pause(0.4)
        var onIt = focusedTab() == title
        for _ in 0..<6 where !onIt {
            remote.press(.right)
            pause(0.6)
            onIt = focusedTab() == title
        }
        for _ in 0..<8 where !onIt {
            remote.press(.left)
            pause(0.6)
            onIt = focusedTab() == title
        }
        guard onIt else { return false }
        note("detail_route_tab_\(title)", "Select on the focused \(title) tab")
        remote.press(.select)
        pause(2)
        return true
    }

    /// Up until a tab-bar button reads focused (Up past the bar is a no-op).
    private func climbToTabBar() -> Bool {
        for _ in 0..<40 {
            if focusedTab() != nil { return true }
            remote.press(.up)
            pause(0.4)
        }
        return focusedTab() != nil
    }

    /// The tab-bar button that reads focused, from ONE snapshot (fourteen per-tab queries per read
    /// made the climb slow on a full Home tree).
    private func focusedTab() -> String? {
        guard let root = try? app.snapshot() else { return nil }
        var hit: String?
        func walk(_ node: XCUIElementSnapshot) {
            guard hit == nil else { return }
            if node.hasFocus, node.elementType == .button,
               let title = Self.tabTitles.first(where: { $0 == node.label || $0 == node.identifier }) {
                hit = title
                return
            }
            node.children.forEach(walk)
        }
        walk(root)
        return hit
    }

    private func railMode() -> Bool {
        app.descendants(matching: .any)["rail_state"].firstMatch.exists
    }

    private func railState() -> String {
        let probe = app.descendants(matching: .any)["rail_state"].firstMatch
        return probe.exists ? probe.label : ""
    }

    private func railFocusedItem() -> Int {
        for token in railState().split(separator: " ") where token.hasPrefix("focused=") {
            return Int(token.dropFirst("focused=".count)) ?? -1
        }
        return -1
    }

    /// Opens the rail by Left (never Menu: Menu inside a Menu-opened rail leaves the app), walks to
    /// the item by the probe's `focused=` id and selects it only once that id reads back.
    private func openRailItem(_ title: String) -> Bool {
        guard let index = Self.railIDs[title] else { return false }
        for attempt in 0..<2 where !railState().contains("expanded=1") {
            if attempt == 1 {
                remote.press(.down)
                pause(1)
            }
            for _ in 0..<15 where !railState().contains("expanded=1") {
                remote.press(.left)
                pause(0.4)
            }
        }
        guard railState().contains("expanded=1") else { return false }
        for _ in 0..<8 where railFocusedItem() != index {
            let focused = railFocusedItem()
            if focused >= 0 { remote.press(focused == 0 && index == 1 ? .down : .up) }
            pause(0.5)
        }
        guard railFocusedItem() == index, railState().contains("expanded=1") else { return false }
        note("detail_route_rail_\(title)", "Select on the focused rail item \(title) — \(railState())")
        remote.press(.select)
        pause(2.5)
        return true
    }

    // MARK: - Shared bits

    private func waitForDetail() -> Bool {
        let play = app.buttons["detail_action_play"]
        let opened = play.waitForExistence(timeout: 30)
        shot(opened ? "detail_route_opened" : "detail_route_no_play")
        return opened
    }

    private func moveFocus(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            pause(0.6)
        }
        return element.exists && element.hasFocus
    }

    /// Labels of every element reporting focus, from one snapshot (for failure messages).
    private func focusedLabels() -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var out: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.hasFocus { out.append(node.label.isEmpty ? "<\(node.identifier)>" : node.label) }
            node.children.forEach(walk)
        }
        walk(root)
        return out
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        print("[DetailRoute] \(name): \(text)")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
