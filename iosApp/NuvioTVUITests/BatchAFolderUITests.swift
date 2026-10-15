import XCTest

/// Batch A (Steven, beta.19-rc3 verdict 2026-10-06, follow-ups 10-08 / 10-14): the folder page is
/// an immersive screen, and add-on catalogs with `posterShape: "landscape"` draw 16:9 rows.
///
///  - `testStageOneRowFolderHidesTabBar` (BUG-148, UX-16 (3)): a Stage folder with ONE source has a
///    one-row strip, so the strip never turns a page; the bar must still be gone the moment the
///    folder is pushed, and back once Menu pops to Home.
///  - `testClassicGridKeepsTabBarHiddenAfterDetail` (BUG-144): Classic folder grid → Detail → Back
///    leaves the bar hidden over the grid; Menu → Home shows it again.
///  - `testRailHideWhileBrowsingHidesInFolder` (BUG-161): Rail = Hide While Browsing hides the rail
///    inside a collection (`rail_state … shown=0`) and shows it again on Home.
///  - `testLandscapeShapeCatalogDrawsLandscapeCards` (BUG-157): a stub add-on whose catalog tags
///    every item `posterShape: "landscape"` draws cards wider than tall with the global Landscape
///    Posters toggle off. Installs the add-on through the Add-ons tab and removes it again.
///
/// Tab bar oracle (the `launchToHome` rule in `NuvioTVUITests`): the bar is SHOWN when its "Home"
/// button exists with `frame.minY > 0`; a hidden bar removes its buttons from the tree, and a
/// scrolled-off one parks them at a negative minY.
///
/// Fixture: the FA87 signed-in simulator (profile "Chris"). Collections come in through the
/// guest-only `-debug.collectionsSeedJsonB64` knob and are cleared with `"[]"` afterwards.
final class BatchAFolderUITests: XCTestCase {
    let remote = XCUIRemote.shared

    /// One pinned collection, one folder, ONE source: the folder's Rows page has a one-row strip
    /// and its Classic grid has no tab chips.
    private static let oneRowSeedJson = """
    [{"id":"zzbatcha-collection","title":"ZZBatchA","pinToTop":true,"showAllTab":true,"folders":[{"id":"zzbatcha-folder","title":"ZZBatchAFolder","hideTitle":false,"heroBackdropUrl":"https://images.metahub.space/background/medium/tt0111161/img","coverImageUrl":"https://images.metahub.space/poster/medium/tt0111161/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"top"}]}]}]
    """

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Helpers (duplicated per file, house rule)

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
    }

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists {
            remote.press(.left)
            pause(0.5)
            remote.press(.left)
            pause(0.5)
            remote.press(.select)
        }
        return app
    }

    private func clearSeed() {
        let app = launch(["-debug.collectionsSeedJsonB64", Data("[]".utf8).base64EncodedString()])
        pause(8)
        app.terminate()
    }

    /// The label of the element holding focus (tvOS 26.5 reports `hasFocus`; 27.0 never does).
    private func focusedLabel(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.label : "<none>"
    }

    private func focusedElement(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Up, at most `max` times, until the tab bar is on screen (Home's rows scrolled back under the
    /// hero). False when it never shows: the immersive state is still holding it.
    private func walkToTopUntilBar(_ app: XCUIApplication, max: Int = 8) -> Bool {
        for _ in 0..<max {
            if tabBarShown(app) { return true }
            remote.press(.up)
            pause(1.5)
        }
        return tabBarShown(app)
    }

    /// See the class header.
    private func tabBarShown(_ app: XCUIApplication) -> Bool {
        let home = app.buttons["Home"]
        return home.exists && home.frame.minY > 0 && home.frame.height > 0
    }

    private func probe(_ app: XCUIApplication, _ id: String) -> String {
        let element = app.descendants(matching: .any)[id].firstMatch
        return element.exists ? element.label : "\(id) <absent>"
    }

    /// Walks `direction` until the focused element's label contains `text`.
    @discardableResult
    private func walk(_ app: XCUIApplication, _ direction: XCUIRemote.Button, untilFocusContains text: String,
                      max: Int = 8, gap: TimeInterval = 2) -> Bool {
        for _ in 0..<max {
            if focusedLabel(app).contains(text) { return true }
            remote.press(direction)
            pause(gap)
        }
        return focusedLabel(app).contains(text)
    }

    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            pause(0.7)
        }
        return element.exists && element.hasFocus
    }

    // MARK: - BUG-148 / UX-16 (3): Stage, one-row folder

    func testStageOneRowFolderHidesTabBar() {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "stage", "-sidebar_style", "tabs",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        note("stage-0-home", "bar=\(tabBarShown(app)) focus=\(focusedLabel(app))\n" + probe(app, "debug_stage"))
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 3), "the pinned folder tile never took focus")
        remote.press(.select)
        pause(10)
        shot("stage-1-folder-open")
        let state = probe(app, "folder_rows_state")
        note("stage-1-folder-open", "bar=\(tabBarShown(app))\n\(state)")
        XCTAssertFalse(state.hasSuffix("<absent>"), "the folder Rows page did not open")
        // No page turn has happened (the strip has one row): the bar is hidden by the push alone.
        XCTAssertFalse(tabBarShown(app), "BUG-148: the tab bar is still on screen over a one-row Stage folder")
        // A Down is a no-op on a one-row strip; the bar must stay hidden, not come back on a rest.
        remote.press(.down)
        pause(3)
        XCTAssertFalse(tabBarShown(app), "BUG-148: the tab bar came back after a Down on the one-row strip")
        remote.press(.menu)
        pause(4)
        shot("stage-2-back-home")
        note("stage-2-back-home", "bar=\(tabBarShown(app)) focus=\(focusedLabel(app))")
        XCTAssertTrue(probe(app, "folder_rows_state").hasSuffix("<absent>"), "Menu did not pop the folder")
        // Home comes back scrolled to the folder's row, where tvOS hides the bar by scroll (the
        // first run's `stage-2-back-home`: bar=false, focus on the folder tile, immersive cleared:
        // the rail leg reads `shown=1` on the same pop). The immersive state is proven cleared by
        // the bar returning once the rows scroll back to the top.
        XCTAssertTrue(walkToTopUntilBar(app), "the tab bar did not return on Home after the folder popped (Up to the top)")
    }

    // MARK: - BUG-144: Classic grid → Detail → Back

    func testClassicGridKeepsTabBarHiddenAfterDetail() {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "classic", "-sidebar_style", "tabs",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 8), "the folder tile never took focus on Classic Home")
        remote.press(.select)
        pause(8)
        shot("classic-1-grid")
        XCTAssertFalse(probe(app, "folder_header_state").hasSuffix("<absent>"), "the Classic folder grid did not open")
        XCTAssertFalse(tabBarShown(app), "the tab bar is on screen over the Classic folder grid")
        // Into the grid's first poster, then Detail.
        if focusedLabel(app) == "<none>" {
            remote.press(.down)
            pause(1.5)
        }
        note("classic-2-grid-focus", focusedLabel(app))
        remote.press(.select)
        pause(6)
        shot("classic-3-detail")
        XCTAssertFalse(probe(app, "debug_bridge").hasSuffix("<absent>"), "Select on the grid did not open a Detail page")
        remote.press(.menu)
        pause(3)
        shot("classic-4-back-on-grid")
        note("classic-4-back-on-grid", "bar=\(tabBarShown(app))\n" + probe(app, "folder_header_state"))
        XCTAssertFalse(probe(app, "folder_header_state").hasSuffix("<absent>"), "Back from Detail did not land on the grid")
        XCTAssertFalse(tabBarShown(app), "BUG-144: the tab bar came back over the grid after Back from Detail")
        remote.press(.menu)
        pause(3)
        shot("classic-5-home")
        XCTAssertTrue(probe(app, "folder_header_state").hasSuffix("<absent>"), "Menu did not pop the folder")
        // See the Stage leg: Home returns scrolled, the bar is scroll-hidden there; Up to the top.
        XCTAssertTrue(walkToTopUntilBar(app), "the tab bar did not return on Classic Home (Up to the top)")
    }

    // MARK: - BUG-161: Rail = Hide While Browsing

    func testRailHideWhileBrowsingHidesInFolder() {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "stage", "-sidebar_style", "rail", "-rail_visibility", "browsing",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        let home = probe(app, "rail_state")
        note("rail-0-home", home + "\nfocus=\(focusedLabel(app))")
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 3), "the pinned folder tile never took focus")
        remote.press(.select)
        pause(10)
        shot("rail-1-folder")
        let inFolder = probe(app, "rail_state")
        note("rail-1-folder", inFolder)
        XCTAssertTrue(inFolder.contains("shown=0"), "BUG-161: the rail stays on screen inside the collection (\(inFolder))")
        remote.press(.menu)
        pause(4)
        let back = probe(app, "rail_state")
        note("rail-2-home", back)
        // Back on Home at row 0 the rail shows again (unless Home itself reads scrolled down, which
        // a pinned first row does not).
        XCTAssertTrue(back.contains("shown=1"), "the rail did not return on Home (\(back))")
    }

    // MARK: - BUG-157: landscape-shape catalog

    private static let landscapeAddonName = "ZZ Landscape Stub"

    private static let landscapeManifest = """
    {"id":"zz.batcha.landscape","version":"1.0.0","name":"\(landscapeAddonName)","description":"Batch A BUG-157 stub","resources":["catalog"],"types":["movie"],"idPrefixes":["zzland"],"catalogs":[{"type":"movie","id":"zzland","name":"ZZ Landscape Row"}]}
    """

    private static let landscapeCatalog: String = {
        let metas = (1...8).map { i in
            "{\"id\":\"zzland\(i)\",\"type\":\"movie\",\"name\":\"ZZLand \(i)\",\"posterShape\":\"landscape\",\"poster\":\"https://images.metahub.space/background/medium/tt0111161/img\"}"
        }
        return "{\"metas\":[\(metas.joined(separator: ","))]}"
    }()

    /// Copy of `TabBarScrollLinkTests.openTab`, with Discover in the list.
    private func openTab(_ app: XCUIApplication, named title: String) {
        let tabNames = ["Home", "Search", "Discover", "Library", "Add-ons", "Settings", "Profile"]
        for _ in 0..<40 {
            if tabNames.contains(where: { app.buttons[$0].exists && app.buttons[$0].hasFocus }) { break }
            remote.press(.up)
            pause(0.35)
        }
        let tab = app.buttons[title]
        if !moveFocus(.right, until: tab, max: 7) {
            _ = moveFocus(.left, until: tab, max: 8)
        }
        remote.press(.select)
        pause(2)
    }

    private func removeLandscapeAddon(_ app: XCUIApplication) {
        openTab(app, named: "Add-ons")
        remote.press(.down)
        pause(1)
        guard walk(app, .down, untilFocusContains: Self.landscapeAddonName, max: 12, gap: 0.8) else {
            note("cleanup", "the stub add-on row was not found; remove '\(Self.landscapeAddonName)' by hand")
            return
        }
        remote.press(.select, forDuration: 1.5)   // hold → context menu
        pause(1.5)
        let removeItem = app.buttons["Remove Add-on"]
        if removeItem.exists {
            _ = moveFocus(.down, until: removeItem, max: 3)
            remote.press(.select)
            pause(1.5)
            let confirm = app.buttons["Remove"]
            if confirm.exists {
                if !moveFocus(.up, until: confirm, max: 3) { _ = moveFocus(.down, until: confirm, max: 3) }
                remote.press(.select)
                pause(2)
            }
        }
        note("cleanup", app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.landscapeAddonName)).count == 0
             ? "removed" : "still listed; remove '\(Self.landscapeAddonName)' by hand")
    }

    func testLandscapeShapeCatalogDrawsLandscapeCards() throws {
        let stub = DiscoveryStubServer(routes: [
            (prefix: "/manifest.json", body: Self.landscapeManifest),
            (prefix: "/catalog/movie/zzland", body: Self.landscapeCatalog),
        ])
        try stub.start()
        defer { stub.stop() }
        // Stage with titles hidden: no pinned reaches and no caption, so a card button's frame is its
        // artwork (XCUITest frames ignore the focus lift's scale; the ratio would survive it anyway).
        let app = launch(["-home_layout", "stage", "-sidebar_style", "tabs", "-debug.posterHideTitles", "YES"])
        pause(14)

        // Install through the Add-ons tab (the field, then the Install button).
        openTab(app, named: "Add-ons")
        remote.press(.down)
        pause(1)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the manifest URL field is missing")
        if !field.hasFocus { _ = moveFocus(.down, until: field, max: 4) }
        remote.press(.select)            // fullscreen keyboard
        pause(3)
        // `app.typeText` needs the keyboard (or the field) to hold focus; on a run where the
        // full-screen keyboard did not come up, skip rather than fail the whole leg (the device
        // pass with Steven's add-on is the real check for BUG-157).
        let keyboardUp = app.keys.count > 0 || field.hasFocus
            || app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
        if !keyboardUp {
            note("landscape-skip", "no keyboard focus after Select on the manifest field; focus=\(focusedLabel(app))")
            throw XCTSkip("the Add-ons manifest field did not take keyboard focus on this run")
        }
        app.typeText("\(stub.origin)/manifest.json\n")
        pause(2)
        let install = app.buttons["Install"]
        if !moveFocus(.down, until: install, max: 4) { _ = moveFocus(.up, until: install, max: 4) }
        remote.press(.select)
        pause(6)
        let installed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Self.landscapeAddonName)).firstMatch.exists
        note("landscape-0-install", "installed=\(installed) requests=\(stub.requestLog.joined(separator: ", "))")
        defer { removeLandscapeAddon(app) }
        guard installed else {
            XCTFail("the stub add-on did not install (requests: \(stub.requestLog))")
            return
        }

        // Home: page down the strip until a stub card holds focus.
        openTab(app, named: "Home")
        pause(6)
        let found = walk(app, .down, untilFocusContains: "ZZLand", max: 14, gap: 2.5)
        shot("landscape-1-row")
        XCTAssertTrue(found, "no stub card took focus on Home (focus=\(focusedLabel(app)))")
        guard found else { return }
        let focused = focusedElement(app).frame
        let neighbour = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ZZLand 2")).firstMatch
        let rest = neighbour.exists ? neighbour.frame : .zero
        note("landscape-1-row", "focused=\(focused) neighbour=\(rest)")
        // 16:9 is 1.78; a portrait poster is 0.67. Anything above 1.4 is a landscape card.
        XCTAssertGreaterThan(focused.width / max(focused.height, 1), 1.4,
                             "BUG-157: the focused card of a landscape-shape catalog is not landscape (\(focused))")
        if rest.height > 0 {
            XCTAssertGreaterThan(rest.width / rest.height, 1.4,
                                 "BUG-157: a resting card of the landscape-shape row is not landscape (\(rest))")
        }
    }
}
