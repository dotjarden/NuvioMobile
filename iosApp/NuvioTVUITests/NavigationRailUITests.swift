import XCTest

/// Home Stage & Strip (W3, 2026-10-05): the navigation rail's UI legs, spec P4 §7.3
/// (`docs/research/home-stage-strip-spec-P4-rail.md`) and W2-D's simulator walk
/// (`RailGateEvidenceTests`). The rail (H9, FEAT-45) replaced FEAT-30's Sidebar mode; these legs
/// replace `test52SidebarOverlay`.
///
/// Oracle: the rail's always-mounted DEBUG probe, `rail_state armed= expanded= focused= reason=
/// gated= vis= shown= tab= route= inset= gmode=`. `focused` is the rail's own `@FocusState` (-1 =
/// none), readable on every runtime; content focus identity (`hasFocus`) is trusted on FA87 (tvOS
/// 26.5) only. The items are `rail_item_<Title>`: plain labels at rest, Buttons while armed.
///
/// Menu discipline (P4 R4, decided Q2): Menu closes a rail that a LEFT opened; inside a rail that
/// Menu (or the hidden-bar redirect, or a re-arm) opened there is no handler, so the system
/// suspends the app. These legs only press Menu with the rail closed, or inside a Left-opened rail;
/// the one deliberate suspend is the very last step of `testRail04`.
///
/// Fixture: FA87 (tvOS 26.5 simulator), guest "Chris" with Cinemeta. In Rail mode there is no tab
/// bar, so the launch lands focus in content: on Stage Home, row 0's first card. Helpers are this
/// file's own (the harness's duplication rule).
final class NavigationRailUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private struct HarnessAbort: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = reason }
    }

    // MARK: - Basics

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[NavigationRailUITests] \(name): \(text)")
    }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.15, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    // MARK: - Launch

    /// Rail mode on a Home layout, with no Upcoming row and no trailers (deterministic rows).
    /// Search & Discover (A6): Discover is the rail's sixth item by default (between Search and
    /// Library); these legs were written against the five-item rail, so they pin the placement Off
    /// (`-discover_placement off`, the DEBUG override) and their item geometry is unchanged.
    /// `testRail11` covers the default.
    private static func railArguments(layout: String = "stage", visibility: String = "always",
                                      discover: String = "off") -> [String] {
        ["-sidebar_style", "rail", "-rail_visibility", visibility, "-home_layout", layout,
         "-home_upcoming_row_enabled", "NO", "-inline_trailers_enabled", "NO", "-discover_placement", discover]
    }

    /// Fresh launch, the profile gate (Left, Left, Select: "Chris" is the first profile), `settle`.
    @discardableResult
    private func launch(_ arguments: [String], settle: TimeInterval = 16) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the FA87 fixture set up?")
        if chris.exists {
            remote.press(.left)
            pause(0.5)
            remote.press(.left)
            pause(0.5)
            remote.press(.select)
        }
        pause(settle)
        return app
    }

    // MARK: - Readouts

    private func label(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        return element.exists ? element.label : ""
    }

    private func railState(_ app: XCUIApplication) -> String { label(app, "rail_state") }

    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0] == Substring(key) else { continue }
            return String(pair[1])
        }
        return nil
    }

    private func rail(_ app: XCUIApplication, _ key: String) -> String? {
        Self.token(railState(app), key)
    }

    private func railFocused(_ app: XCUIApplication) -> Int {
        Int(rail(app, "focused") ?? "") ?? -1
    }

    private func railExpanded(_ app: XCUIApplication) -> Bool { rail(app, "expanded") == "1" }

    /// Menu is safe to press only with the rail closed and holding no focus (inside a rail that Menu,
    /// the redirect or a re-arm opened, Menu suspends the app).
    private func menuIsSafe(_ app: XCUIApplication) -> Bool {
        rail(app, "expanded") == "0" && railFocused(app) < 0
    }

    private func requireRail(_ app: XCUIApplication) throws {
        guard poll(10, step: 0.5, { !railState(app).isEmpty }) else {
            throw HarnessAbort("rail_state never appeared with -sidebar_style rail (DEBUG build? the rail mounted?)")
        }
    }

    // MARK: - Focus

    private struct Focused {
        let label: String
        let identifier: String
        let frame: CGRect
    }

    private func focusedNodes(_ app: XCUIApplication) -> [Focused] {
        guard let root = try? app.snapshot() else { return [] }
        var out: [Focused] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.hasFocus { out.append(Focused(label: node.label, identifier: node.identifier, frame: node.frame)) }
            node.children.forEach(walk)
        }
        walk(root)
        return out
    }

    private func focused(_ app: XCUIApplication) -> Focused? { focusedNodes(app).first }

    /// The leftmost card in the focused element's row band (cards are buttons; same vertical band,
    /// card-sized). With focus on card 1, this is card 0 at rest: no focus lift in its frame.
    private func leftmostCardInFocusedRow(_ app: XCUIApplication) -> CGRect? {
        guard let item = focused(app), let root = try? app.snapshot() else { return nil }
        var frames: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .button, node.frame.width >= 100, node.frame.height >= 100,
               abs(node.frame.midY - item.frame.midY) < 60, !node.identifier.hasPrefix("rail_item_") {
                frames.append(node.frame)
            }
            node.children.forEach(walk)
        }
        walk(root)
        return frames.min { $0.minX < $1.minX }
    }

    // MARK: - Rail driving

    /// Presses Left until the rail opens, recording the focused label before every press; `origin`
    /// is the element the opening Left started from. Never presses Menu.
    private func openRailByLeft(_ app: XCUIApplication, maxPresses: Int = 12) -> (opened: Bool, origin: String) {
        var origin = focused(app)?.label ?? ""
        for _ in 0..<maxPresses {
            if railExpanded(app) { return (true, origin) }
            origin = focused(app)?.label ?? origin
            remote.press(.left)
            if poll(1.0, { railExpanded(app) }) { return (true, origin) }
        }
        return (railExpanded(app), origin)
    }

    @discardableResult
    private func moveRailFocus(_ app: XCUIApplication, to index: Int) -> Bool {
        for _ in 0..<10 {
            let current = railFocused(app)
            if current == index { return true }
            if current >= 0 { remote.press(current < index ? .down : .up) }
            pause(0.5)
        }
        return railFocused(app) == index
    }

    /// Switches to tab `index` through the rail (opened by Left), and waits out the hand-off ladder.
    private func openTabViaRail(_ app: XCUIApplication, index: Int) throws {
        guard openRailByLeft(app, maxPresses: 15).opened else {
            throw HarnessAbort("the rail never opened from a Left walk — \(railState(app))")
        }
        guard moveRailFocus(app, to: index) else {
            throw HarnessAbort("could not move the rail's focus to item \(index) — \(railState(app))")
        }
        remote.press(.select)
        pause(2.5)
    }

    // MARK: - Settings root (testRail04, testRail09)

    private static let settingsRootOrder: [(title: String, raw: String)] = [
        ("Account & Profiles", "accountProfiles"), ("Services", "services"), ("Appearance", "appearance"),
        ("Home Screen", "homeScreen"), ("Detail Page", "detailPage"), ("Player", "player"),
        ("Sources", "sources"), ("Subtitles & Audio", "subtitlesAudio"), ("About", "about"),
        ("Developer", "developer"),
    ]

    private func settingsRootPresent(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["settings_root_list"].exists
            || app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'settings_category_'"))
                .firstMatch.exists
    }

    private func focusedSettingsRootTitle(_ app: XCUIApplication) -> String? {
        let nodes = focusedNodes(app)
        for node in nodes where node.identifier.hasPrefix("settings_category_") {
            let raw = String(node.identifier.dropFirst("settings_category_".count))
            if let entry = Self.settingsRootOrder.first(where: { $0.raw == raw }) { return entry.title }
        }
        for node in nodes {
            if let entry = Self.settingsRootOrder.first(where: { node.label.hasPrefix($0.title) }) { return entry.title }
        }
        return nil
    }

    /// With the Settings root showing, focuses `title` by walking Down, then Up.
    @discardableResult
    private func focusSettingsRootRow(_ app: XCUIApplication, named title: String) -> Bool {
        if focusedSettingsRootTitle(app) == title { return true }
        for _ in 0..<10 {
            remote.press(.down)
            pause(0.6)
            if focusedSettingsRootTitle(app) == title { return true }
        }
        for _ in 0..<10 {
            remote.press(.up)
            pause(0.6)
            if focusedSettingsRootTitle(app) == title { return true }
        }
        return false
    }

    // MARK: - Search keyboard (testRail05b)

    private func searchKeyboardHasFocus(_ app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists, let root = try? keyboard.snapshot() else { return false }
        func walk(_ node: XCUIElementSnapshot) -> Bool { node.hasFocus || node.children.contains(where: walk) }
        return walk(root)
    }

    // MARK: - testRail01 (+ Rail02, Rail03, Menu in a Left-opened rail)

    /// P4 Rail01–03 on Stage Home (the spike's and W2-D's device-proven walk): Left mid-row moves
    /// along the row and never opens the rail; Left from the row's first card opens it (`reason=left`,
    /// Home's item focused, content gated, the pill at its labelled width); Right returns to that
    /// same card through Home's route; and Menu inside a Left-opened rail closes it (R4) back to the
    /// same card, the app still in the foreground.
    func testRail01_LeftEntersRailFromFirstCardOnly() throws {
        let app = launch(Self.railArguments())
        try requireRail(app)
        let start = railState(app)
        XCTAssertEqual(Self.token(start, "expanded"), "0", "the rail must not hold focus at launch: \(start)")
        XCTAssertEqual(Self.token(start, "armed"), "0", "the rail must not be armed at rest: \(start)")
        XCTAssertFalse(app.buttons["rail_item_Search"].exists, "rail items are plain labels at rest, never buttons the engine can land on")
        remote.press(.down)
        pause(2.5)
        let card0 = focused(app)?.label ?? ""
        remote.press(.right)
        pause(1.2)
        let card1 = focused(app)?.label ?? ""
        remote.press(.right)
        pause(1.2)
        XCTAssertNotEqual(focused(app)?.label ?? "", card0, "precondition: Right ×2 must move along the row")

        // Rail02: Left mid-row moves back along the row.
        remote.press(.left)
        pause(1.2)
        XCTAssertEqual(rail(app, "expanded"), "0", "Left mid-row must not open the rail: \(railState(app))")
        XCTAssertEqual(focused(app)?.label, card1, "Left mid-row must move to the previous card")
        remote.press(.left)
        pause(1.2)
        XCTAssertEqual(rail(app, "expanded"), "0", "Left onto the first card must not open the rail yet: \(railState(app))")
        XCTAssertEqual(focused(app)?.label, card0, "two Lefts must reach the row's first card")

        // Rail01: Left from the first card has no target, so the rail arms.
        remote.press(.left)
        XCTAssertTrue(poll(2.0) { railExpanded(app) }, "Left from the row's first card must open the rail: \(railState(app))")
        let opened = railState(app)
        shot("rail01_open")
        XCTAssertEqual(Self.token(opened, "reason"), "left", "\(opened)")
        XCTAssertEqual(Self.token(opened, "focused"), "0", "the rail opens on the current tab's item (Home): \(opened)")
        XCTAssertEqual(Self.token(opened, "gated"), "1", "content must be gated while the rail holds focus: \(opened)")
        XCTAssertTrue(app.buttons["rail_item_Home"].exists, "armed rail items must be buttons")
        let pill = app.descendants(matching: .any)["navigation_rail"].firstMatch
        XCTAssertTrue(pill.exists, "navigation_rail must be on screen")
        if pill.exists {
            XCTAssertGreaterThan(pill.frame.width, 200, "the open rail must expand to its labelled width (300; 84 collapsed): \(pill.frame)")
        }

        // Rail03: Right returns to the same card through Home's route.
        remote.press(.right)
        XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" && rail(app, "gated") == "0" },
                      "Right must close the rail and open the content gate: \(railState(app))")
        let closed = railState(app)
        XCTAssertEqual(Self.token(closed, "armed"), "0", "\(closed)")
        XCTAssertEqual(Self.token(closed, "route"), "home", "the exit must restore through Home's route: \(closed)")
        XCTAssertTrue(poll(1.5) { focused(app)?.label == card0 }, "Right must return to the card the rail was opened from ('\(card0)'), got '\(focused(app)?.label ?? "<none>")'")
        shot("rail01_right_back")

        // R4: Menu closes a rail that Left opened, back to the same card.
        remote.press(.left)
        XCTAssertTrue(poll(2.0) { railExpanded(app) }, "Left from the first card must open the rail again: \(railState(app))")
        XCTAssertEqual(rail(app, "reason"), "left", "\(railState(app))")
        remote.press(.menu)
        XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" }, "Menu must close a Left-opened rail: \(railState(app))")
        XCTAssertEqual(app.state, .runningForeground, "Menu inside a Left-opened rail closes it; it must not leave the app")
        XCTAssertTrue(poll(1.5) { focused(app)?.label == card0 }, "Menu's close must return to the card the rail was opened from")
    }

    /// P4 Rail01 on Classic Home: a Left walk along a catalog row opens the rail from the row's first
    /// card, and Right returns there through the Classic route (`PinnedRowFocusRequest`).
    func testRail01b_LeftEntersRailFromClassicRow() throws {
        let app = launch(Self.railArguments(layout: "classic"))
        try requireRail(app)
        XCTAssertTrue(app.staticTexts["debug_hero"].waitForExistence(timeout: 10), "Classic Home did not come up")
        // The launch lands on the hero CTA; two Downs reach the catalog rows.
        remote.press(.down)
        pause(1.5)
        remote.press(.down)
        pause(2.0)
        remote.press(.right)
        pause(1.2)
        let result = openRailByLeft(app)
        XCTAssertTrue(result.opened, "a Left walk along a Classic row must open the rail from its first card: \(railState(app))")
        guard result.opened else { return }
        let opened = railState(app)
        XCTAssertEqual(Self.token(opened, "reason"), "left", "\(opened)")
        XCTAssertEqual(Self.token(opened, "gated"), "1", "\(opened)")
        shot("rail01b_open")
        remote.press(.right)
        XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        XCTAssertEqual(rail(app, "route"), "home", "the exit must restore through Classic Home's route: \(railState(app))")
        XCTAssertTrue(poll(2.0) { focused(app)?.label == result.origin },
                      "Right must return to the row's first card ('\(result.origin)'), got '\(focused(app)?.label ?? "<none>")'")
    }

    // MARK: - testRail04

    /// P4 Rail04: Menu at a tab root opens the rail (`reason=menu`, the tab's own item focused) and
    /// Right closes it: Stage Home at row 0, the Add-ons root (Cinemeta's row always gives it a
    /// focus target; the guest Library can be empty), and the Settings root, where the exit must land
    /// back on the category last opened (the root's landing correction, #21). LAST STEP, by design:
    /// Menu inside a Menu-opened rail leaves the app (Q2).
    func testRail04_MenuAtTabRootOpensRail() throws {
        let app = launch(Self.railArguments())
        try requireRail(app)
        let home0 = focused(app)?.label ?? ""

        // Home, row 0.
        XCTAssertTrue(menuIsSafe(app), "precondition: rail closed — \(railState(app))")
        remote.press(.menu)
        XCTAssertTrue(poll(2.5) { railExpanded(app) }, "Menu at the top of Home must open the rail: \(railState(app))")
        XCTAssertEqual(rail(app, "reason"), "menu", "\(railState(app))")
        XCTAssertEqual(rail(app, "focused"), "0", "\(railState(app))")
        remote.press(.right)
        XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        XCTAssertTrue(poll(1.5) { focused(app)?.label == home0 }, "Right must return to row 0's card ('\(home0)')")

        // Add-ons root.
        try openTabViaRail(app, index: 3)
        XCTAssertTrue(poll(3.0) { rail(app, "tab") == "3" && menuIsSafe(app) },
                      "Select on Add-ons must switch tab and hand focus to its content: \(railState(app))")
        if menuIsSafe(app) {
            remote.press(.menu)
            XCTAssertTrue(poll(2.5) { railExpanded(app) }, "Menu at the Add-ons root must open the rail: \(railState(app))")
            XCTAssertEqual(rail(app, "reason"), "menu", "\(railState(app))")
            XCTAssertEqual(rail(app, "focused"), "3", "\(railState(app))")
            remote.press(.right)
            XCTAssertTrue(poll(3.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        }

        // Settings root, after opening a category and popping back to the root.
        try openTabViaRail(app, index: 4)
        guard poll(6.0, { settingsRootPresent(app) }) else {
            XCTFail("the Settings root never appeared after selecting rail_item_Settings — \(railState(app))")
            return
        }
        XCTAssertTrue(focusSettingsRootRow(app, named: "Appearance"), "could not focus Appearance on the Settings root")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["settings_pane_appearance"].waitForExistence(timeout: 4), "Appearance did not push")
        pause(1.0)
        XCTAssertTrue(menuIsSafe(app), "precondition: rail closed inside the pane — \(railState(app))")
        remote.press(.menu)
        XCTAssertTrue(poll(4.0) { settingsRootPresent(app) }, "Menu inside the pane must pop to the root")
        pause(1.0)
        XCTAssertEqual(focusedSettingsRootTitle(app), "Appearance", "the pop must return focus to Appearance")
        XCTAssertTrue(menuIsSafe(app), "the pop must not open the rail — \(railState(app))")
        remote.press(.menu)
        XCTAssertTrue(poll(2.5) { railExpanded(app) }, "Menu at the Settings root must open the rail: \(railState(app))")
        XCTAssertEqual(rail(app, "reason"), "menu", "\(railState(app))")
        XCTAssertEqual(rail(app, "focused"), "4", "\(railState(app))")
        remote.press(.right)
        XCTAssertTrue(poll(3.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        XCTAssertTrue(poll(3.0) { focusedSettingsRootTitle(app) == "Appearance" },
                      "the rail exit must land back on Appearance (the root's landing correction, #21) — focused: \(focusedSettingsRootTitle(app) ?? "<none>")")
        shot("rail04_settings_back")

        // LAST STEP (Q2, P4 R4): Menu at the root opens the rail; Menu again, inside that
        // Menu-opened rail, has no handler and the system suspends the app.
        guard menuIsSafe(app) else { return }
        remote.press(.menu)
        guard poll(2.5, { railExpanded(app) }) else {
            XCTFail("Menu at the Settings root did not open the rail the second time: \(railState(app))")
            return
        }
        XCTAssertEqual(rail(app, "reason"), "menu", "\(railState(app))")
        remote.press(.menu)
        // The tvOS simulator shows the Home screen ~2 s after the press, and `app.state` can trail
        // it: wait longer, and take the Home screen (HeadBoard) in front as the same evidence.
        let headBoard = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
        XCTAssertTrue(poll(8.0, step: 0.5) { app.state != .runningForeground || headBoard.state == .runningForeground },
                      "Menu inside a Menu-opened rail must leave the app (the remote's normal grammar, Q2)")
    }

    // MARK: - testRail05

    /// P4 Rail05: focus stays inside the open rail. Down ×8 reaches the profile item (5) and stops;
    /// Up ×8 reaches Home (0) and stops; the rail stays expanded and content gated throughout, and
    /// nothing in content takes focus.
    func testRail05_FocusStaysInsideTheRail() throws {
        let app = launch(Self.railArguments())
        try requireRail(app)
        guard openRailByLeft(app).opened else {
            XCTFail("Left from row 0's first card did not open the rail: \(railState(app))")
            return
        }
        var leaks: [String] = []
        func check(_ step: String) {
            let state = railState(app)
            if Self.token(state, "expanded") != "1" || Self.token(state, "gated") != "1" {
                leaks.append("\(step): \(state)")
            }
            let outside = focusedNodes(app).filter { !$0.identifier.hasPrefix("rail_item_") && $0.identifier != "navigation_rail" }
            if !outside.isEmpty { leaks.append("\(step): content focus \(outside.map { "\($0.identifier)|\($0.label)" })") }
        }
        for i in 1...8 {
            remote.press(.down)
            pause(0.5)
            check("down\(i)")
        }
        XCTAssertEqual(rail(app, "focused"), "5", "Down ×8 must stop on the last item (the profile): \(railState(app))")
        shot("rail05_bottom")
        for i in 1...8 {
            remote.press(.up)
            pause(0.5)
            check("up\(i)")
        }
        XCTAssertEqual(rail(app, "focused"), "0", "Up ×8 must stop on the first item (Home): \(railState(app))")
        XCTAssertTrue(leaks.isEmpty, "focus left the rail, or the rail closed, mid-walk: \(leaks)")
        remote.press(.right)
        XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
    }

    /// P4 Rail05b: the same containment from the Search keyboard, the rail opened by Menu through
    /// the hidden-bar redirect (S1 carried into the rail): the keyboard never takes focus while the
    /// rail holds it, and Right hands focus back to it. Never presses Menu inside that rail.
    func testRail05b_FocusStaysInsideTheRailOverSearch() throws {
        let app = launch(Self.railArguments())
        try requireRail(app)
        try openTabViaRail(app, index: 1)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6), "the Search keyboard must be up")
        XCTAssertTrue(poll(3.0) { menuIsSafe(app) }, "the rail must hand focus to Search: \(railState(app))")
        guard menuIsSafe(app) else { return }
        remote.press(.menu)
        XCTAssertEqual(app.state, .runningForeground, "Menu from the Search keyboard must not leave the app")
        guard poll(3.0, { railExpanded(app) }) else {
            XCTFail("Menu from the Search keyboard must open the rail through the hidden-bar redirect: \(railState(app))")
            return
        }
        XCTAssertEqual(rail(app, "reason"), "hiddenBarRedirect", "\(railState(app))")
        var keyboardTookFocus: [String] = []
        for i in 1...8 {
            remote.press(.down)
            pause(0.5)
            if searchKeyboardHasFocus(app) || !railExpanded(app) { keyboardTookFocus.append("down\(i): \(railState(app))") }
        }
        for i in 1...8 {
            remote.press(.up)
            pause(0.5)
            if searchKeyboardHasFocus(app) || !railExpanded(app) { keyboardTookFocus.append("up\(i): \(railState(app))") }
        }
        XCTAssertTrue(keyboardTookFocus.isEmpty, "focus left the rail for the keyboard mid-walk: \(keyboardTookFocus)")
        XCTAssertEqual(rail(app, "focused"), "0", "\(railState(app))")
        remote.press(.right)
        XCTAssertTrue(poll(4.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        pause(2.6) // the hand-off ladder's last check on Search
        XCTAssertTrue(searchKeyboardHasFocus(app), "Right must hand focus back to the Search keyboard")
    }

    // MARK: - testRail06

    /// P4 Rail06: Select on another item switches tab and hands focus to that tab's content: the
    /// Settings root (always focusable; the guest Library can be empty, where the designed fallback
    /// re-arms the rail).
    func testRail06_SelectSwitchesTab() throws {
        let app = launch(Self.railArguments())
        try requireRail(app)
        guard openRailByLeft(app).opened else {
            XCTFail("Left from row 0's first card did not open the rail: \(railState(app))")
            return
        }
        XCTAssertTrue(moveRailFocus(app, to: 4), "could not move the rail's focus to Settings: \(railState(app))")
        remote.press(.select)
        XCTAssertTrue(poll(2.5) { rail(app, "tab") == "4" && railFocused(app) < 0 && rail(app, "expanded") == "0" },
                      "Select must switch to Settings and hand focus to its content: \(railState(app))")
        XCTAssertTrue(poll(4.0) { settingsRootPresent(app) }, "the Settings root must be on screen")
        XCTAssertNotNil(focusedSettingsRootTitle(app), "focus must land on a Settings root row")
        shot("rail06_settings")
    }

    // MARK: - testRail07

    /// P4 Rail07 (Stage, Hide While Browsing): shown at row 0 with no inset; a Down hides it with the
    /// page and moves no content sideways; Up brings it back with the page (no resting settle, #8);
    /// on Search it stays hidden (R7).
    func testRail07_HideWhileBrowsing() throws {
        let app = launch(Self.railArguments(visibility: "browsing"))
        try requireRail(app)
        let start = railState(app)
        XCTAssertEqual(Self.token(start, "vis"), "browsing", "\(start)")
        XCTAssertEqual(Self.token(start, "shown"), "1", "the rail must show at row 0: \(start)")
        XCTAssertEqual(Self.token(start, "inset"), "0", "Hide While Browsing reserves no width: \(start)")
        let x0 = focused(app)?.frame.minX
        remote.press(.down)
        XCTAssertTrue(poll(1.0, step: 0.05) { rail(app, "shown") == "0" }, "the rail must hide once the strip leaves row 0: \(railState(app))")
        pause(1.5)
        let x1 = focused(app)?.frame.minX
        if let x0, let x1 {
            XCTAssertEqual(x1, x0, accuracy: 1, "hiding the rail must not move content sideways")
        }
        remote.press(.up)
        XCTAssertTrue(poll(0.8, step: 0.05) { rail(app, "shown") == "1" }, "the rail must come back with the page to row 0: \(railState(app))")
        shot("rail07_back_at_top")
        try openTabViaRail(app, index: 1)
        XCTAssertTrue(poll(3.0) { rail(app, "tab") == "1" && rail(app, "shown") == "0" },
                      "Hide While Browsing keeps the rail hidden on Search (R7): \(railState(app))")
    }

    // MARK: - testRail08

    /// P4 Rail08 (Always Visible): the collapsed pill ends by x 101 and every tab root's content moves
    /// 36 pt right — row card 0 at 176 on Stage and on Classic (140 in a Tabs-mode run).
    func testRail08_AlwaysVisibleInset() throws {
        let app = launch(Self.railArguments())
        try requireRail(app)
        // The DEBUG bounds element is the pill's own frame (`navigation_rail` is a `.contain`
        // container whose frame is the union of its children, faded labels included).
        let pill = app.descendants(matching: .any)["navigation_rail_bounds"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 4), "navigation_rail must show in Always Visible")
        XCTAssertLessThanOrEqual(pill.frame.maxX, 101, "the collapsed pill must end by x 101: \(pill.frame)")
        XCTAssertEqual(rail(app, "inset"), "36", "\(railState(app))")
        remote.press(.right)
        pause(1.2)
        let stageCard0 = leftmostCardInFocusedRow(app)
        XCTAssertNotNil(stageCard0, "no card frames in the focused row")
        if let stageCard0 { XCTAssertEqual(stageCard0.minX, 176, accuracy: 2, "Stage: card 0 at 140 + 36: \(stageCard0)") }

        let classic = launch(Self.railArguments(layout: "classic"))
        try requireRail(classic)
        remote.press(.down)
        pause(1.5)
        remote.press(.down)
        pause(2.0)
        remote.press(.right)
        pause(1.2)
        let classicCard0 = leftmostCardInFocusedRow(classic)
        XCTAssertNotNil(classicCard0, "no card frames in the focused Classic row")
        if let classicCard0 { XCTAssertEqual(classicCard0.minX, 176, accuracy: 2, "Classic: card 0 at 140 + 36: \(classicCard0)") }

        let tabs = launch(["-sidebar_style", "tabs", "-home_layout", "stage",
                           "-home_upcoming_row_enabled", "NO", "-inline_trailers_enabled", "NO", "-discover_placement", "off"])
        XCTAssertTrue(railState(tabs).isEmpty, "Tabs mode must not mount the rail")
        for _ in 0..<2 where !(focused(tabs).map({ $0.frame.midY > 500 }) ?? false) {
            remote.press(.down)
            pause(1.5)
        }
        remote.press(.right)
        pause(1.2)
        let tabsCard0 = leftmostCardInFocusedRow(tabs)
        if let tabsCard0 { XCTAssertEqual(tabsCard0.minX, 140, accuracy: 2, "Tabs: card 0 at 140: \(tabsCard0)") }
        note("rail08", "stage=\(stageCard0.map { "\($0)" } ?? "-") classic=\(classicCard0.map { "\($0)" } ?? "-") tabs=\(tabsCard0.map { "\($0)" } ?? "-")")
    }

    // MARK: - testRail09

    /// P4 Rail09: FEAT-30's stored value `sidebar_style "sidebar"` reads as Rail (the one-time
    /// persistent migration to "rail" is unit-tested; a launch argument is never persisted): the rail
    /// mounts, Home's `debug_navchrome` says `mode=rail`, and Appearance's Navigation row reads Rail
    /// with the Rail visibility row under it.
    func testRail09_SidebarValueReadsAsRail() throws {
        let app = launch(["-sidebar_style", "sidebar", "-home_layout", "stage",
                          "-home_upcoming_row_enabled", "NO", "-inline_trailers_enabled", "NO", "-discover_placement", "off"])
        try requireRail(app)
        XCTAssertTrue(app.descendants(matching: .any)["navigation_rail"].waitForExistence(timeout: 4), "navigation_rail must show")
        let chrome = label(app, "debug_navchrome")
        XCTAssertTrue(chrome.contains("mode=rail"), "\"sidebar\" must read as Rail: \(chrome)")
        try openTabViaRail(app, index: 4)
        guard poll(6.0, { settingsRootPresent(app) }) else {
            XCTFail("the Settings root never appeared — \(railState(app))")
            return
        }
        XCTAssertTrue(focusSettingsRootRow(app, named: "Appearance"), "could not focus Appearance")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["settings_pane_appearance"].waitForExistence(timeout: 4), "Appearance did not push")
        let navigationRow = app.descendants(matching: .any)["appearance_row_navigation"].firstMatch
        for _ in 0..<14 where !navigationRow.exists {
            remote.press(.down)
            pause(0.5)
        }
        pause(0.8)
        shot("rail09_appearance")
        XCTAssertTrue(navigationRow.exists, "appearance_row_navigation never materialised in the Appearance pane")
        let value = (navigationRow.value as? String) ?? ""
        let readsRail = value == "Rail" || navigationRow.label.contains("Rail")
            || app.descendants(matching: .any)["appearance_row_rail"].exists
        XCTAssertTrue(readsRail, "the Navigation row must read Rail for \"sidebar\" (label '\(navigationRow.label)', value '\(value)')")
    }

    // MARK: - testRail10

    /// P4 Rail10 (+ Rail08's Detail half): on a Detail page pushed from Stage Home the rail shows,
    /// the page's actions clear it (Play at x ≥ 116), a Left from the leftmost action opens it, and
    /// Right returns to that same action through Detail's route.
    func testRail10_DetailRoundTrip() throws {
        let app = launch(Self.railArguments() + ["-debug.trailerProbe", "YES", "-debug.trailerForceNoTrailer", "YES",
                                                 "-detail_layout", "cinematic"])
        try requireRail(app)
        remote.press(.select)
        let actionLabels = ["Mark Watched", "Watched", "Add to Library", "In Library"]
        guard poll(20, step: 0.5, {
            app.descendants(matching: .any)["detail_hero"].exists || actionLabels.contains(where: { app.buttons[$0].exists })
        }) else {
            XCTFail("Select on row 0's first card did not open a Detail page")
            return
        }
        pause(3.0)
        let pill = app.descendants(matching: .any)["navigation_rail"].firstMatch
        XCTAssertTrue(pill.exists, "Always Visible keeps the rail on a pushed Detail page")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume' OR label BEGINSWITH 'Up Next'")).firstMatch
        if play.exists {
            XCTAssertGreaterThanOrEqual(play.frame.minX, 116, "Detail's actions must clear the rail (x ≥ 116): \(play.frame)")
        }
        let result = openRailByLeft(app, maxPresses: 6)
        XCTAssertTrue(result.opened, "a Left from Detail's leftmost action must open the rail: \(railState(app))")
        guard result.opened else { return }
        XCTAssertEqual(rail(app, "reason"), "left", "\(railState(app))")
        shot("rail10_open_over_detail")
        remote.press(.right)
        XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        XCTAssertEqual(rail(app, "route"), "detail", "the exit must restore through Detail's route: \(railState(app))")
        XCTAssertTrue(poll(1.5) { focused(app)?.label == result.origin },
                      "Right must return to the action the rail was opened from ('\(result.origin)'), got '\(focused(app)?.label ?? "<none>")'")
        XCTAssertTrue(app.descendants(matching: .any)["detail_hero"].exists || actionLabels.contains(where: { app.buttons[$0].exists }),
                      "Right must return into Detail, never pop it")
    }

    // MARK: - testRail11 (Search & Discover A6)

    /// At the default placement (Own Tab) the rail carries a Discover item (`rail_item_Discover`,
    /// id 6) directly under Search, and selecting it opens the Discover tab (`rail_state tab=6`, the
    /// grid-first Discover page's `discover_grid_state` mounted: FEAT-73, Steven rc4).
    func testRail11_DiscoverItemAtDefault() throws {
        let app = launch(Self.railArguments(discover: "tab"))
        try requireRail(app)
        let item = app.descendants(matching: .any)["rail_item_Discover"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 4), "the rail must carry rail_item_Discover at the default placement")
        let search = app.descendants(matching: .any)["rail_item_Search"].firstMatch
        let library = app.descendants(matching: .any)["rail_item_Library"].firstMatch
        if item.exists, search.exists, library.exists {
            XCTAssertGreaterThan(item.frame.midY, search.frame.midY, "Discover sits below Search: \(item.frame) vs \(search.frame)")
            XCTAssertLessThan(item.frame.midY, library.frame.midY, "Discover sits above Library: \(item.frame) vs \(library.frame)")
        }
        guard openRailByLeft(app, maxPresses: 15).opened else {
            throw HarnessAbort("the rail never opened from a Left walk — \(railState(app))")
        }
        // Visual order Home 0, Search 1, Discover 6: two Downs from Home.
        for _ in 0..<6 where railFocused(app) != 6 {
            let current = railFocused(app)
            remote.press(current == 0 || current == 1 ? .down : .up)
            pause(0.5)
        }
        XCTAssertEqual(railFocused(app), 6, "focus must reach the Discover item — \(railState(app))")
        shot("rail11_discover_item")
        guard railFocused(app) == 6 else { return }
        remote.press(.select)
        XCTAssertTrue(poll(6) { rail(app, "tab") == "6" }, "selecting Discover must switch to tab 6 — \(railState(app))")
        XCTAssertTrue(app.descendants(matching: .any)["discover_grid_state"].firstMatch.waitForExistence(timeout: 8),
                      "the Discover tab must mount the grid-first Discover page (discover_grid_state)")
        pause(2)
        shot("rail11_discover_tab")
    }

    // MARK: - testRail12 (FEAT-80 Corner, Batch N; Batch O)

    /// Batch O geometry: the Corner rail is Centre's pill at (16, 38), so its 60 pt Home cell is at
    /// (16 + 12, 38 + 22), centred on (58, 90), at rest and open. Five tabs (Discover off) plus
    /// the avatar: 6 × 60 + 5 × 14 + 18 + 2 × 22 = 492.
    private static let cornerPillOrigin = CGPoint(x: 16, y: 38)
    private static let cornerHomeCellCentre = CGPoint(x: 58, y: 90)
    private static let cornerColumnHeight: CGFloat = 492
    private static let cornerItemTitles = ["Home", "Search", "Library", "Add-ons", "Settings", "Profile"]

    private func railItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any)["rail_item_\(title)"].firstMatch
    }

    private func railGlass(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["navigation_rail_bounds"].firstMatch
    }

    /// The Home cell's centre from `rail_item_Home`'s frame. At rest the item is a `.combine`
    /// element whose frame is its children's union: the 36 pt house glyph (as wide as its box,
    /// centred in the cell), plus the faded label with Labels Shown, so the glyph's leading edge
    /// + 18 and the frame's centre line. Open it is a Button whose frame is the 60 pt row, plus
    /// the focus capsule's 4 × 2 pt outset (RailItemButtonStyle) while focused (64 tall), so its
    /// leading edge (+ 4 when focused) + 30.
    private static func homeCellCentre(_ frame: CGRect, open: Bool) -> CGPoint {
        guard open else { return CGPoint(x: frame.minX + 18, y: frame.midY) }
        let outset: CGFloat = frame.height > 62 ? 4 : 0
        return CGPoint(x: frame.minX + outset + 30, y: frame.midY)
    }

    /// At rest: the bare Home glyph in the pill's Home cell, hittable; no glass (the DEBUG oracle is
    /// mounted only while the glass shows); the lower items out of the tree. Returns Home's frame.
    @discardableResult
    private func assertCornerAtRest(_ app: XCUIApplication, _ step: String) -> CGRect {
        XCTAssertTrue(poll(3.0) { !railGlass(app).exists }, "\(step): no glass at rest — \(railGlass(app).frame)")
        let home = railItem(app, "Home")
        XCTAssertTrue(home.exists, "\(step): the Home glyph shows at rest")
        XCTAssertTrue(home.isHittable, "\(step): the Home glyph is the one visible item")
        let frame = home.frame
        let centre = Self.homeCellCentre(frame, open: false)
        XCTAssertEqual(centre.x, Self.cornerHomeCellCentre.x, accuracy: 2, "\(step): Home sits in the pill's Home cell: \(frame)")
        XCTAssertEqual(centre.y, Self.cornerHomeCellCentre.y, accuracy: 2, "\(step): Home sits on the top safe-area line: \(frame)")
        // The masked items drop their identifiers while collapsed. Their glyph and title still show
        // in this snapshot: the tvOS 27 simulator's XCUITest tree lists children even under
        // `.combine` / `.ignore` elements (Home's own cell shows both), so it cannot see
        // `accessibilityHidden`; the identifier is the oracle.
        for title in Self.cornerItemTitles.dropFirst() {
            XCTAssertFalse(railItem(app, title).exists, "\(step): rail_item_\(title) must be hidden at rest")
        }
        return frame
    }

    /// Open: Centre's pill at (16, 38), `width` wide, the column's height, inside the screen with a
    /// gap on every side, every item inside it. Returns the glass's frame.
    @discardableResult
    private func assertCornerOpen(_ app: XCUIApplication, width: CGFloat, _ step: String) -> CGRect {
        for title in Self.cornerItemTitles {
            XCTAssertTrue(railItem(app, title).exists, "\(step): rail_item_\(title) must exist once the pill unrolls")
        }
        let glass = railGlass(app)
        XCTAssertTrue(glass.exists, "\(step): the glass shows while the rail is open")
        let column = glass.frame
        XCTAssertEqual(column.minX, Self.cornerPillOrigin.x, accuracy: 1, "\(step): Centre's bezel inset: \(column)")
        XCTAssertEqual(column.minY, Self.cornerPillOrigin.y, accuracy: 1, "\(step): anchored at the top, never flush: \(column)")
        XCTAssertEqual(column.width, width, accuracy: 2, "\(step): Centre's pill width: \(column)")
        XCTAssertEqual(column.height, Self.cornerColumnHeight, accuracy: 4, "\(step): the column's height: \(column)")
        let screen = app.frame
        XCTAssertTrue(column.minX > 0 && column.minY > 0 && column.maxX < screen.maxX && column.maxY < screen.maxY,
                      "\(step): every corner inside the screen with a gap: \(column) in \(screen)")
        for title in Self.cornerItemTitles {
            let frame = railItem(app, title).frame
            XCTAssertTrue(frame.minY >= column.minY && frame.maxY <= column.maxY,
                          "\(step): rail_item_\(title) inside the glass: \(frame) vs \(column)")
        }
        return column
    }

    /// FEAT-80 Corner, `-rail_position corner` (Batch O, Christian's 2026-10-20 mock: the open rail
    /// is Centre's pill, the resting rail a bare Home icon).
    ///  - Always Visible, Icons Only, at rest: only the Home glyph, no glass, in the pill's Home
    ///    cell; no reserved width (`inset=0`, `pos=corner`).
    ///  - Menu at Home row 0: the pill unrolls at (16, 38), 84 × the column; Home's cell has not
    ///    moved. Right closes it back to the bare glyph.
    ///  - The same with Labels Shown: 300 wide open, the same resting glyph.
    ///  - rc8's stored Top reads as Corner (`pos=corner`).
    ///  - Hidden: nothing at rest; Menu opens the full pill.
    /// Frames and existence only: the tvOS 27 simulator never reports `hasFocus`.
    func testRail12_CornerTabUnrolls() throws {
        for (labels, width) in [("icons", CGFloat(84)), ("shown", CGFloat(300))] {
            let app = launch(Self.railArguments() + ["-rail_position", "corner", "-rail_labels", labels])
            try requireRail(app)
            XCTAssertEqual(rail(app, "pos"), "corner", "\(railState(app))")
            XCTAssertEqual(rail(app, "inset"), "0", "Corner reserves no width: \(railState(app))")
            assertCornerAtRest(app, "\(labels) rest")
            shot("rail12_corner_rest_\(labels)")

            // Menu at Home row 0 unrolls the pill.
            XCTAssertTrue(menuIsSafe(app), "precondition: rail closed — \(railState(app))")
            remote.press(.menu)
            XCTAssertTrue(poll(2.5) { railExpanded(app) }, "\(labels): Menu must open the Corner rail: \(railState(app))")
            pause(0.8)   // the spring settles
            assertCornerOpen(app, width: width, "\(labels) open")
            // Home's cell never moves: the open row's cell is where the resting glyph sat.
            let homeOpen = railItem(app, "Home").frame
            let openCentre = Self.homeCellCentre(homeOpen, open: true)
            XCTAssertEqual(openCentre.x, Self.cornerHomeCellCentre.x, accuracy: 2, "\(labels): Home's cell never moves: \(homeOpen)")
            XCTAssertEqual(openCentre.y, Self.cornerHomeCellCentre.y, accuracy: 2, "\(labels): Home's row never moves: \(homeOpen)")
            shot("rail12_corner_open_\(labels)")
            remote.press(.right)
            XCTAssertTrue(poll(2.0) { rail(app, "expanded") == "0" }, "\(labels): Right must close the rail: \(railState(app))")
            XCTAssertTrue(poll(2.0) { !railItem(app, "Search").exists }, "\(labels): the pill rolls back up to the Home glyph")
            pause(0.6)   // the shrink, then the glass's fade
            assertCornerAtRest(app, "\(labels) closed")
        }

        // rc8's stored Top reads as Corner.
        let legacy = launch(Self.railArguments() + ["-rail_position", "top"])
        try requireRail(legacy)
        XCTAssertEqual(rail(legacy, "pos"), "corner", "a stored Top reads as Corner: \(railState(legacy))")

        // Hidden: nothing at rest; Menu opens the full pill.
        let hidden = launch(Self.railArguments(visibility: "hidden") + ["-rail_position", "corner", "-rail_labels", "icons"])
        try requireRail(hidden)
        XCTAssertEqual(rail(hidden, "shown"), "0", "\(railState(hidden))")
        XCTAssertFalse(hidden.descendants(matching: .any)["navigation_rail"].exists, "Corner + Hidden shows nothing at rest")
        XCTAssertFalse(railItem(hidden, "Home").exists, "Corner + Hidden shows nothing at rest")
        XCTAssertFalse(railGlass(hidden).exists, "Corner + Hidden shows no glass at rest")
        guard menuIsSafe(hidden) else { return }
        remote.press(.menu)
        XCTAssertTrue(poll(2.5) { railExpanded(hidden) }, "Menu must open the hidden Corner rail: \(railState(hidden))")
        pause(0.8)
        assertCornerOpen(hidden, width: 84, "hidden open")
        shot("rail12_corner_hidden_open")
        remote.press(.right)
        XCTAssertTrue(poll(2.0) { rail(hidden, "shown") == "0" }, "Right must close the hidden rail: \(railState(hidden))")
    }

    /// FEAT-80 Corner, Batch N review r1: the rail opens on a LOWER tab. The items below Home fade in
    /// staggered with the unroll, and `takeFocusAfterReveal` writes focus to the selected tab's item
    /// the next turn and at +0.15 s; on hardware an item still near opacity 0 refuses focus, so the
    /// selected tab's item is drawn at full opacity from the arm. Here (Labels Shown, the default):
    /// switch to Settings through the Corner rail; at the Settings root the rail rests as the bare
    /// Home glyph; Menu there opens the pill (Batch O: Centre's, 300 wide at (16, 38)) with focus on
    /// Settings (4), every item inside the glass. Frames and the probe only: the tvOS 27 simulator
    /// never reports `hasFocus`.
    func testRail12b_CornerOpensOnTheSettingsTab() throws {
        let app = launch(Self.railArguments() + ["-rail_position", "corner"])
        try requireRail(app)
        XCTAssertEqual(rail(app, "pos"), "corner", "\(railState(app))")

        // Home row 0: Menu opens the pill; move to Settings and select it.
        XCTAssertTrue(menuIsSafe(app), "precondition: rail closed — \(railState(app))")
        remote.press(.menu)
        guard poll(2.5, { railExpanded(app) }) else {
            XCTFail("Menu must open the Corner rail on Home: \(railState(app))")
            return
        }
        XCTAssertTrue(moveRailFocus(app, to: 4), "could not move the rail's focus to Settings: \(railState(app))")
        remote.press(.select)
        XCTAssertTrue(poll(3.0) { rail(app, "tab") == "4" && menuIsSafe(app) },
                      "Select must switch to Settings and hand focus to its content: \(railState(app))")
        guard poll(6.0, { settingsRootPresent(app) }) else {
            XCTFail("the Settings root never appeared after selecting rail_item_Settings — \(railState(app))")
            return
        }
        XCTAssertTrue(poll(3.0) { !railItem(app, "Search").exists }, "the pill rolls back up to the Home glyph on the Settings tab")
        pause(1.0)
        assertCornerAtRest(app, "settings rest")
        shot("rail12b_corner_rest_on_settings")

        // Menu at the Settings root: the pill unrolls with focus on Settings.
        guard menuIsSafe(app) else {
            XCTFail("precondition: rail closed on the Settings root — \(railState(app))")
            return
        }
        remote.press(.menu)
        XCTAssertTrue(poll(2.5) { railExpanded(app) }, "Menu at the Settings root must open the Corner rail: \(railState(app))")
        XCTAssertTrue(poll(1.5) { railFocused(app) == 4 }, "focus must land on the Settings item: \(railState(app))")
        pause(0.8)   // the spring and the staggered fades settle
        let column = assertCornerOpen(app, width: 300, "settings open")
        let settings = railItem(app, "Settings")
        if settings.exists {
            let frame = settings.frame
            XCTAssertFalse(frame.isEmpty, "the Settings item is laid out: \(frame)")
            XCTAssertGreaterThan(frame.minY, railItem(app, "Add-ons").frame.minY, "Settings sits below Add-ons: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxY, column.maxY, "the glass reaches past the Settings item: \(frame) vs \(column)")
        }
        shot("rail12b_corner_open_on_settings")
        XCTAssertEqual(rail(app, "expanded"), "1", "the rail is still open with focus on Settings: \(railState(app))")
        remote.press(.right)
        XCTAssertTrue(poll(3.0) { rail(app, "expanded") == "0" }, "Right must close the rail: \(railState(app))")
        XCTAssertTrue(poll(3.0) { focusedSettingsRootTitle(app) != nil }, "the rail exit must land on a Settings root row")
    }
}
