import XCTest

/// Detail + Settings revamp (2026-10-02): screenshot harness for the design checkpoints (Gate 1/2).
/// Not a pass/fail leg: each test opens one surface through the `-debug.openDeepLink` hook (or the
/// Settings tab), attaches screenshots plus the accessibility tree, and asserts only that it got
/// there. Attachments are pulled out of the .xcresult into
/// `docs/research/detail-settings-revamp-sim-evidence/`.
final class RevampEvidenceTests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tree(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.6) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    /// ui-legs (2026-10-22): the focused Settings ROOT row, by its `settings_category_<raw>`
    /// identifier or by a focused label starting with the category title (a List row's focus can
    /// sit on its Cell, which carries the label but not the identifier — first full run).
    private static let rootTitles: [String: String] = [
        "accountProfiles": "Account & Profiles", "services": "Services", "appearance": "Appearance",
        "homeScreen": "Home Screen", "detailPage": "Detail Page", "player": "Player", "sources": "Sources",
        "subtitlesAudio": "Subtitles & Audio", "about": "About", "developer": "Developer",
    ]

    private func rootRowFocused(_ app: XCUIApplication, _ raw: String) -> Bool {
        guard let title = Self.rootTitles[raw], let root = try? app.snapshot() else { return false }
        func walk(_ node: XCUIElementSnapshot) -> Bool {
            if node.hasFocus, node.identifier == "settings_category_\(raw)" || node.label.hasPrefix(title) { return true }
            return node.children.contains(where: walk)
        }
        return walk(root)
    }

    /// ui-legs (2026-10-22): whether an element with `identifier` holds focus, from one snapshot.
    private func focusedIdentifier(_ app: XCUIApplication, _ identifier: String) -> Bool {
        guard let root = try? app.snapshot() else { return false }
        func walk(_ node: XCUIElementSnapshot) -> Bool {
            (node.hasFocus && node.identifier == identifier) || node.children.contains(where: walk)
        }
        return walk(root)
    }

    /// ui-legs: Select only when `isTarget()` holds on a focus read made right here; otherwise a
    /// screenshot, a failure naming what was focused, and no press.
    @discardableResult
    private func selectIfFocused(_ app: XCUIApplication, _ what: String, when isTarget: () -> Bool) -> Bool {
        if isTarget() {
            remote.press(.select)
            return true
        }
        shot("unverified-\(what)")
        var focused: [String] = []
        if let root = try? app.snapshot() {
            func walk(_ node: XCUIElementSnapshot) {
                if node.hasFocus { focused.append(node.label.isEmpty ? "<\(node.identifier)>" : node.label) }
                node.children.forEach(walk)
            }
            walk(root)
        }
        XCTFail("\(what): focus is not on the intended element (focused: \(focused)) — not pressing Select")
        return false
    }

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists {
            // ui-legs: the shared verified step (Select only once "Chris" reads focused; a blind
            // Right here would hit Add Profile).
            DetailEntryRoute.selectChrisTile(self, app, timeout: 5)
        }
        return app
    }

    private func detail(_ name: String, url: String, layout: String = "cinematic", settle: TimeInterval = 14) {
        let app = launch(["-debug.openDeepLink", url, "-detail_layout", layout])
        pause(settle)
        shot("\(name)-landing")
        tree(app, "\(name)-tree")
        pause(8)
        shot("\(name)-settled")
    }

    func testDetailMovie() {
        detail("detail-movie-dune", url: "nuviotv://title?id=tt15239678&type=movie&name=Dune")
    }

    func testDetailSeries() {
        detail("detail-series-the100", url: "nuviotv://title?id=tt2661044&type=series&name=The%20100")
    }

    func testDetailLongSynopsis() {
        detail("detail-long-synopsis", url: "nuviotv://title?id=tt0903747&type=series&name=Breaking%20Bad")
    }

    func testDetailNoLogo() {
        detail("detail-no-logo", url: "nuviotv://title?id=tt0050083&type=movie&name=12%20Angry%20Men")
    }

    func testDetailNoBackdrop() {
        detail("detail-obscure", url: "nuviotv://title?id=tt0000417&type=movie&name=A%20Trip%20to%20the%20Moon")
    }

    func testDetailClassic() {
        detail("detail-classic-dune", url: "nuviotv://title?id=tt15239678&type=movie&name=Dune", layout: "classic")
    }

    func testDetailSynopsisSheetAndScroll() {
        // ui-legs (2026-10-22): trailer auto-play off (device-local, never synced) so the teaser stays
        // on screen; the full-screen auto-play cover otherwise holds focus by the time Up is pressed.
        let app = launch(["-debug.openDeepLink", "nuviotv://title?id=tt0903747&type=series&name=Breaking%20Bad",
                          "-detail_trailer_autoplay", "NO"])
        pause(25)
        // Up from Play reaches the teaser when it is truncated.
        press(.up)
        pause(1)
        shot("detail-teaser-focused")
        // ui-legs: only the teaser BUTTON (a truncated synopsis) opens a sheet, and it must hold
        // focus. The plain-text teaser also carries the id; matching it pressed Select on whatever
        // held focus — on this fixture "Mark Watched" (Play is "Playback unavailable"), since
        // Breaking Bad's synopsis fits four lines (debug_detail_hero trunc=0, with or without TMDB).
        if app.buttons["detail_synopsis_teaser"].exists,
           selectIfFocused(app, "teaser", when: { focusedIdentifier(app, "detail_synopsis_teaser") }) {
            pause(2)
            shot("detail-synopsis-sheet")
            tree(app, "detail-synopsis-sheet-tree")
            remote.press(.menu)
            pause(2)
            shot("detail-after-sheet-menu")
        }
        press(.down, times: 2, gap: 1.2)
        pause(2)
        shot("detail-down-into-rows")
    }

    func testSettingsRootAndPane() {
        let app = launch([])
        pause(8)
        let settings = app.buttons["Settings"]
        press(.up, times: 6, gap: 0.4)
        for _ in 0..<8 where !(settings.exists && settings.hasFocus) {
            remote.press(.right)
            pause(0.5)
        }
        guard selectIfFocused(app, "settings-tab", when: { settings.exists && settings.hasFocus }) else { return }
        pause(3)
        press(.down)
        pause(1.5)
        shot("settings-root")
        tree(app, "settings-root-tree")
        press(.down, times: 3, gap: 0.8)
        // ui-legs: the root does not always open on its first row (first full run: Down x3 read
        // "Detail Page"), so step to Home Screen one row at a time, reading focus after each press.
        for step in 0..<10 where !rootRowFocused(app, "homeScreen") {
            remote.press(step < 3 ? .up : .down)
            pause(0.7)
        }
        shot("settings-root-homescreen-focused")
        guard selectIfFocused(app, "home-screen-row", when: { rootRowFocused(app, "homeScreen") }) else { return }
        pause(2.5)
        shot("settings-pane-homescreen")
        press(.down, times: 2, gap: 0.8)
        shot("settings-pane-homescreen-row2")
        tree(app, "settings-pane-tree")
        remote.press(.menu)
        pause(2)
        shot("settings-after-pop")
    }

    @discardableResult
    private func openSettings(_ app: XCUIApplication) -> Bool {
        let settings = app.buttons["Settings"]
        press(.up, times: 6, gap: 0.4)
        for _ in 0..<8 where !(settings.exists && settings.hasFocus) {
            remote.press(.right)
            pause(0.5)
        }
        guard selectIfFocused(app, "settings-tab", when: { settings.exists && settings.hasFocus }) else { return false }
        pause(3)
        press(.down)
        pause(1.5)
        return true
    }

    func testSettingsEveryPane() {
        let app = launch([])
        pause(8)
        guard openSettings(app) else { return }
        // Anchor on the first category, then walk the fixed root order.
        // Up×12 parks focus on the tab bar; one Down lands on the first category.
        press(.up, times: 12, gap: 0.3)
        press(.down)
        pause(1)
        shot("settings-root-top")
        let names = ["account", "services", "appearance", "homescreen", "detailpage",
                     "player", "sources", "subtitles", "about", "developer"]
        // ui-legs (2026-10-22): each Select goes only to the root row it names (read by its
        // `settings_category_<raw>` identifier), and the Account & Profiles pane is not opened on
        // the signed-in fixture (its rows include Sign Out and Switch Profile): stepped past.
        let raws = ["accountProfiles", "services", "appearance", "homeScreen", "detailPage",
                    "player", "sources", "subtitlesAudio", "about", "developer"]
        for (index, name) in names.enumerated() {
            if raws[index] == "accountProfiles" {
                shot("pane-\(index)-\(name)-not-opened")
                press(.down)
                pause(0.8)
                continue
            }
            guard selectIfFocused(app, "root-row-\(raws[index])", when: { rootRowFocused(app, raws[index]) }) else { return }
            pause(2.5)
            shot("pane-\(index)-\(name)-top")
            press(.down, times: 2, gap: 0.8)
            shot("pane-\(index)-\(name)-row")
            if index == 0 { tree(app, "pane-account-tree") }
            remote.press(.menu)
            pause(2)
            if index == 0 { shot("pane-0-after-pop") }
            press(.down)
            pause(0.8)
        }
    }

    func testDetailHeroMotion() {
        // ui-legs (2026-10-22): trailer auto-play off (device-local, never synced): in the first full
        // run the Dune trailer had gone full screen by the teaser step (nothing reported focus).
        let app = launch(["-debug.openDeepLink", "nuviotv://title?id=tt15239678&type=movie&name=Dune",
                          "-detail_trailer_autoplay", "NO"])
        pause(14)
        shot("motion-landing")
        press(.down)
        pause(2.5)
        shot("motion-down-from-hero")
        press(.up)
        pause(2.5)
        shot("motion-up-back-to-hero")
        press(.up)
        pause(1.5)
        shot("motion-teaser-focused")
        // ui-legs: the sheet step needs a truncated synopsis (the teaser BUTTON) holding focus. This
        // fixture's tt15239678 (Dune: Part Two) synopsis fits four lines with or without TMDB, Up
        // stays on "Mark Watched" (Play is "Playback unavailable"), and the blind Select here would
        // have marked the title watched on the account: noted and skipped instead.
        if app.buttons["detail_synopsis_teaser"].exists {
            guard selectIfFocused(app, "motion-teaser", when: { focusedIdentifier(app, "detail_synopsis_teaser") }) else { return }
            pause(2.5)
            shot("motion-synopsis-sheet")
            remote.press(.menu)
            pause(2)
        } else {
            add(XCTAttachment(string: "NOTE: no teaser button (the synopsis fits four lines) — the sheet step was skipped"))
        }
        press(.down, times: 14, gap: 1.0)
        pause(2)
        shot("motion-bottom-about")
        tree(app, "motion-bottom-tree")
    }
}
