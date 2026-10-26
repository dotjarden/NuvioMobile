import XCTest

/// Add-ons hub C (H2 seed of H5's `AddonsHubUITests`): the hub is up with its summary and action
/// cards and the installed list on the FA87 fixture (Chris, which has add-ons), the first add-on
/// card takes focus and its four controls are reachable by Right. Prints `[HubLeg]` lines and
/// dwells 2 s per state so a screenshot from outside the runner can read each one.
///
/// Launch: `-home_layout classic -debug.rememberLastProfile NO -debug.trailerForceNoTrailer YES`;
/// the Chris tile is the shared verified step. No Select on a card control (nothing is changed on
/// the fixture: no toggle, no move, no remove, no install).
final class AddonsHubUITests: XCTestCase {
    let remote = XCUIRemote.shared

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func say(_ text: String) { print("[HubLeg] \(text)") }

    /// Identifiers only: a card's label carries the add-on host, which stays out of the logs.
    private func focusDump(_ app: XCUIApplication) -> String {
        let nodes = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        return nodes.isEmpty ? "<none>" : nodes.map { "[id=\($0.identifier)]" }.joined(separator: " ")
    }

    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, until target: XCUIElement, max: Int) -> Bool {
        for _ in 0..<max {
            if target.exists && target.hasFocus { return true }
            remote.press(direction)
            pause(0.4)
        }
        return target.exists && target.hasFocus
    }

    private func openTab(_ app: XCUIApplication, named title: String) {
        let tabNames = ["Home", "Search", "Discover", "Library", "Add-ons", "Settings", "Profile"]
        for _ in 0..<40 {
            if tabNames.contains(where: { app.buttons[$0].exists && app.buttons[$0].hasFocus }) { break }
            remote.press(.up)
            pause(0.35)
        }
        let tab = app.buttons[title]
        if !moveFocus(.right, until: tab, max: 7) { _ = moveFocus(.left, until: tab, max: 8) }
        XCTAssertTrue(tab.hasFocus, "the \(title) tab never took focus; focused: \(focusDump(app))")
        remote.press(.select)
        pause(2)
    }

    func testHubCardsAndFirstAddonCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-home_layout", "classic", "-debug.rememberLastProfile", "NO",
                               "-debug.trailerForceNoTrailer", "YES", "-detail_trailer_autoplay", "NO"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists { DetailEntryRoute.selectChrisTile(self, app, timeout: 5) }
        pause(10)

        openTab(app, named: "Add-ons")
        XCTAssertTrue(element(app, "addons_hub_root").waitForExistence(timeout: 10), "addons_hub_root never appeared; focused: \(focusDump(app))")
        for id in ["addons_hub_summary_addons", "addons_hub_summary_catalogs", "addons_hub_summary_debrid",
                   "addons_hub_action_install", "addons_hub_action_refresh", "addons_hub_installed_title"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), "\(id) missing")
        }
        say("hub up; plugins card: \(element(app, "addons_hub_summary_plugins").exists); phone card: \(element(app, "addons_hub_action_phone").exists)")
        pause(2)

        // Focus into the page: the first summary card, then the action row, then card 0.
        if !element(app, "addons_hub_summary_addons").hasFocus { remote.press(.down); pause(0.8) }
        say("after Down: \(focusDump(app))")
        pause(2)
        remote.press(.down); pause(0.8)
        say("action row: \(focusDump(app))")
        pause(2)
        let card0 = element(app, "addons_hub_card_0")
        XCTAssertTrue(card0.waitForExistence(timeout: 15), "no addons_hub_card_0 on the fixture (does Chris have add-ons?); empty=\(element(app, "addons_hub_empty").exists)")
        remote.press(.down); pause(0.8)
        XCTAssertTrue(moveFocus(.down, until: card0, max: 3), "card 0 never took focus; focused: \(focusDump(app))")
        say("card 0: exists=\(card0.exists) hasFocus=\(card0.hasFocus) enabled=\(card0.isEnabled)")
        pause(2)
        // The single-card fixture: Up and Down are disabled (no neighbour) and so skipped by
        // focus; Right from Toggle lands on Remove.
        for control in ["toggle", "remove"] {
            remote.press(.right); pause(0.6)
            let node = element(app, "addons_hub_card_0_\(control)")
            say("Right -> \(control): exists=\(node.exists) enabled=\(node.isEnabled) hasFocus=\(node.hasFocus)")
            XCTAssertTrue(node.exists && node.hasFocus, "\(control) never took focus; focused: \(focusDump(app))")
            pause(1.5)
        }
        for control in ["up", "down"] {
            let node = element(app, "addons_hub_card_0_\(control)")
            XCTAssertTrue(node.exists, "\(control) control missing")
            XCTAssertFalse(node.isEnabled, "\(control) should be disabled on the single-card fixture")
        }
        // Up on the remove control must stay inside the installed list or go to the action row,
        // never leave the hub.
        remote.press(.up); pause(0.8)
        let actions = ["addons_hub_action_install", "addons_hub_action_refresh", "addons_hub_action_phone"]
        let focusedAction = actions.first { element(app, $0).exists && element(app, $0).hasFocus }
        say("Up from controls: focused action card: \(focusedAction ?? "<none>")")
        XCTAssertNotNil(focusedAction, "focus after the final Up is not an addons_hub_action_* card; focused: \(focusDump(app))")
        XCTAssertTrue(element(app, "addons_hub_root").exists, "the hub went away")
        pause(2)
    }

    /// H3: the Install action card opens the install sheet with the URL field focused, and Menu
    /// closes the sheet with focus back on the Install card. No URL is typed; nothing installs.
    func testInstallSheetOpensAndCancels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-home_layout", "classic", "-debug.rememberLastProfile", "NO",
                               "-debug.trailerForceNoTrailer", "YES", "-detail_trailer_autoplay", "NO"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists { DetailEntryRoute.selectChrisTile(self, app, timeout: 5) }
        pause(10)

        openTab(app, named: "Add-ons")
        XCTAssertTrue(element(app, "addons_hub_root").waitForExistence(timeout: 10), "addons_hub_root never appeared; focused: \(focusDump(app))")
        let install = element(app, "addons_hub_action_install")
        XCTAssertTrue(install.waitForExistence(timeout: 5), "addons_hub_action_install missing")

        remote.press(.down); pause(0.8)
        if !moveFocus(.down, until: install, max: 3) {
            if !moveFocus(.left, until: install, max: 3) { _ = moveFocus(.right, until: install, max: 3) }
        }
        XCTAssertTrue(install.hasFocus, "the Install action card never took focus; focused: \(focusDump(app))")
        say("install card focused")
        pause(2)

        remote.press(.select); pause(1.5)
        let field = element(app, "addons_hub_install_field")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the install sheet did not open; focused: \(focusDump(app))")
        XCTAssertTrue(field.hasFocus, "the URL field does not hold focus; focused: \(focusDump(app))")
        say("sheet open: \(focusDump(app))")
        pause(2)

        remote.press(.menu); pause(1.5)
        XCTAssertFalse(element(app, "addons_hub_install_field").exists, "the sheet is still up after Menu")
        XCTAssertTrue(install.exists && install.hasFocus, "focus did not return to the Install card; focused: \(focusDump(app))")
        say("sheet closed: \(focusDump(app))")
        pause(2)
    }
}
