import XCTest

/// Wave 3b W3-10 (GitHub #10 FEAT-84) and W3-7 (BUG-213): screenshot harness, not a pass/fail leg.
/// It opens Subtitles & Audio, walks the language rows (recording the explainer title and each
/// row's value), records where a `Menu { Picker }` opens (the Size menu: first entry or checked
/// entry?), opens the pushed Audio / Subtitles language pages and records where focus lands, and
/// repeats the Audio page in French; the W3-7 legs walk the key field → Save Key rows. Nothing is
/// ever selected on the (synced) fixture profile: Menu closes every menu and page. PNGs and notes
/// go to `docs/research/wave3b-sim-2026-10-21/` as `wb-*`. FA87 fixture (tvOS 26.5, `hasFocus`
/// works).
final class Wave3bLanguageEvidenceUITests: XCTestCase {

    let remote = XCUIRemote.shared

    private static let outDir = "/Users/christianturnbull/Claude/Projects/Nuvio tvOS/docs/research/wave3b-sim-2026-10-21"
    /// Root order (matches `NuvioTVUITests.settingsRootOrder`); Subtitles & Audio is index 7.
    private static let subtitlesAudioIndex = 7

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.6) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = URL(fileURLWithPath: Self.outDir).appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = URL(fileURLWithPath: Self.outDir).appendingPathComponent("\(name).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Every node that reports focus, from ONE snapshot: identifier, label, value, frame.
    private func focusedNodes(_ app: XCUIApplication) -> String {
        guard let root = try? app.snapshot() else { return "(no snapshot)" }
        var out: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.hasFocus {
                out.append("id=<\(node.identifier)> label=<\(node.label)> value=<\(String(describing: node.value ?? ""))> selected=\(node.isSelected) type=\(node.elementType.rawValue) frame=\(node.frame)")
            }
            node.children.forEach(walk)
        }
        walk(root)
        return out.isEmpty ? "(nothing reports focus)" : out.joined(separator: "\n")
    }

    /// Launches and picks the "Chris" profile. Throws (skips) unless "Chris" itself holds focus
    /// before Select: a blind Select once landed on Add Profile and typed into its form.
    private func launch(extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-home_layout", "classic", "-settings_style", "default"] + extra
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        guard chris.waitForExistence(timeout: 90) else { throw XCTSkip("profile picker never appeared") }
        pause(1.5)
        note("wb-0-profile-picker", app.buttons.allElementsBoundByIndex.map(\.label).joined(separator: "\n"))
        for _ in 0..<4 where !chris.hasFocus {
            remote.press(.left)
            pause(0.6)
        }
        guard chris.hasFocus else {
            app.terminate()
            throw XCTSkip("the Chris profile never took focus on the picker; not pressing Select blind")
        }
        remote.press(.select)
        pause(10)
        return app
    }

    /// Settings tab ("Settings" / "Paramètres") → root → the category `raw` (root index
    /// `index`) pushed. Every Select is guarded: the Settings tab must hold focus, then the root
    /// row `settings_category_<raw>` must, and the pane must appear; otherwise the leg is skipped
    /// without pressing Select (a blind Select once opened the Profile tab and created profiles).
    private func openPane(_ app: XCUIApplication, raw: String, index: Int, settingsTitle: String, rowTitle: String) throws {
        let settings = app.buttons[settingsTitle]
        press(.up, times: 6, gap: 0.4)
        for _ in 0..<8 {
            if settings.exists && settings.hasFocus { break }
            remote.press(.right)
            pause(0.5)
        }
        guard settings.exists && settings.hasFocus else {
            throw XCTSkip("the \(settingsTitle) tab never took focus; focus: \(focusedNodes(app))")
        }
        remote.press(.select)
        pause(3)
        press(.up, times: 12, gap: 0.3)
        press(.down)
        pause(1)
        press(.down, times: index, gap: 0.7)
        pause(0.8)
        let rowID = "settings_category_\(raw)"
        let focus = focusedNodes(app)
        guard focus.contains("id=<\(rowID)>") || focus.contains("label=<\(rowTitle)") else {
            throw XCTSkip("the root row \(rowID) (\(rowTitle)) never took focus; focus: \(focus)")
        }
        remote.press(.select)
        pause(2.5)
        guard app.descendants(matching: .any)["settings_pane_\(raw)"].waitForExistence(timeout: 6) else {
            throw XCTSkip("pane \(raw) never appeared")
        }
    }

    private func openSubtitlesPane(_ app: XCUIApplication, settingsTitle: String) throws {
        try openPane(app, raw: "subtitlesAudio", index: Self.subtitlesAudioIndex, settingsTitle: settingsTitle,
                     rowTitle: settingsTitle == "Settings" ? "Subtitles & Audio" : "Sous-titres et audio")
    }

    /// Guard before a Select on a pane row: the explainer must name `rowTitle`.
    private func requireRow(_ app: XCUIApplication, _ rowTitle: String) throws {
        guard explainer(app) == rowTitle else {
            throw XCTSkip("expected the \(rowTitle) row before Select; explainer=\(explainer(app))")
        }
    }

    /// Guard before a Select on a language page row: the page is up (its pane is gone, its
    /// title shows) and a list cell holds focus.
    private func requirePageRow(_ app: XCUIApplication, pane raw: String, title: String) throws {
        let onPage = !app.descendants(matching: .any)["settings_pane_\(raw)"].exists
            && app.staticTexts[title].exists
        let focus = focusedNodes(app)
        guard onPage, focus.contains("type=75"), !focus.contains("label=<>") else {
            throw XCTSkip("expected a focused row on the \(title) page before Select; focus: \(focus)")
        }
    }

    private func explainer(_ app: XCUIApplication) -> String {
        let title = app.staticTexts["settings_explainer_title"]
        return title.exists ? title.label : "(none)"
    }

    /// Walks Down until the explainer reads `rowTitle`. Returns whether it got there.
    private func walk(_ app: XCUIApplication, to rowTitle: String, max: Int = 16) -> Bool {
        for _ in 0..<max {
            if explainer(app) == rowTitle { return true }
            remote.press(.down)
            pause(0.6)
        }
        return explainer(app) == rowTitle
    }

    /// The value the picker row titled `title` reports (its `LabeledContent` value).
    private func rowValue(_ app: XCUIApplication, _ title: String) -> String {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        guard row.exists else { return "(absent)" }
        return "label=<\(row.label)> value=<\(String(describing: row.value ?? ""))>"
    }

    // MARK: English: the rows, where a Menu opens, and where the language pages open

    func testLanguageRowsAndPages() throws {
        let app = try launch()
        try openSubtitlesPane(app, settingsTitle: "Settings")

        // Where does a tvOS Menu { Picker } open? The Size menu (Medium is the stored size).
        _ = walk(app, to: "Size")
        try requireRow(app, "Size")
        remote.press(.select)
        pause(1.5)
        shot("wb-5b-size-menu-open")
        note("wb-5b-size-menu-open-focus", focusedNodes(app))
        remote.press(.menu)
        pause(1.2)

        XCTAssertTrue(walk(app, to: "Audio"), "never reached the Audio row; explainer=\(explainer(app))")
        pause(0.8)
        shot("wb-1-pane-audio-focused")
        note("wb-1-values", [
            "Audio: \(rowValue(app, "Audio"))",
            "Fallback Audio Language: \(rowValue(app, "Fallback Audio Language"))",
            "Subtitles: \(rowValue(app, "Subtitles"))",
            "Fallback Subtitle Language: \(rowValue(app, "Fallback Subtitle Language"))",
            "focus: \(focusedNodes(app))",
        ].joined(separator: "\n"))

        remote.press(.down)
        pause(0.9)
        note("wb-2-explainer", explainer(app))
        XCTAssertEqual(explainer(app), "Fallback Audio Language", "Down from Audio must land on Fallback Audio Language")
        shot("wb-2-pane-fallback-audio-focused")

        remote.press(.down)
        pause(0.9)
        note("wb-3-explainer", explainer(app))
        shot("wb-3-pane-subtitles-focused")
        remote.press(.down)
        pause(0.9)
        note("wb-3b-explainer", "after one more Down: \(explainer(app)) (Subtitles = Off hides Fallback Subtitle Language)")

        // The Audio page: pushed, focus on the checked row; Menu pops back to the Audio row.
        _ = walkUp(app, to: "Audio")
        try requireRow(app, "Audio")
        remote.press(.select)
        pause(2.0)
        shot("wb-4-audio-page-open")
        note("wb-4-audio-page-open-focus", focusedNodes(app))
        press(.down, times: 6, gap: 0.4)
        pause(0.6)
        shot("wb-4b-audio-page-after-6-down")
        note("wb-4b-audio-page-after-6-down-focus", focusedNodes(app))
        remote.press(.menu)
        pause(1.5)
        note("wb-4c-after-page-pop", "explainer=\(explainer(app))\n\(focusedNodes(app))")
        XCTAssertEqual(explainer(app), "Audio", "Menu on the Audio page must pop back to the Audio row")

        // The Subtitles page.
        _ = walk(app, to: "Subtitles", max: 4)
        try requireRow(app, "Subtitles")
        remote.press(.select)
        pause(2.0)
        shot("wb-5-subtitles-page-open")
        note("wb-5-subtitles-page-open-focus", focusedNodes(app))
        remote.press(.menu)
        pause(1.5)
        remote.press(.menu)
        pause(1.5)
    }

    private func walkUp(_ app: XCUIApplication, to rowTitle: String, max: Int = 6) -> Bool {
        for _ in 0..<max {
            if explainer(app) == rowTitle { return true }
            remote.press(.up)
            pause(0.6)
        }
        return explainer(app) == rowTitle
    }

    // MARK: W3-7 (BUG-213): the key field and Save Key are two rows

    /// Root index of a category (matches `NuvioTVUITests.settingsRootOrder`).
    private static let rootIndex = ["services": 1, "sources": 6]

    /// Pushes `category`, walks Down until the explainer title satisfies `isField`, then one Down
    /// must land on "Save Key" (its own row and focus target) and one Up must come back. Never
    /// presses Select, so nothing is typed or saved.
    private func keySplitEvidence(category: String, tag: String, isField: (String) -> Bool) throws {
        let app = try launch()
        try openPane(app, raw: category, index: Self.rootIndex[category]!, settingsTitle: "Settings",
                     rowTitle: category == "services" ? "Services" : "Sources")
        var reached = false
        for _ in 0..<40 {
            if isField(explainer(app)) { reached = true; break }
            remote.press(.down)
            pause(0.5)
        }
        note("\(tag)-1-field-explainer", "reached=\(reached) explainer=\(explainer(app))\n\(focusedNodes(app))")
        guard reached else {
            XCTFail("never reached a key field row in \(category) (no entry row shown for this profile?)")
            return
        }
        pause(0.8)
        shot("\(tag)-1-field-focused")
        remote.press(.down)
        pause(0.9)
        note("\(tag)-2-save-explainer", "explainer=\(explainer(app))\n\(focusedNodes(app))")
        XCTAssertEqual(explainer(app), "Save Key", "Down from the key field must land on the Save Key row")
        shot("\(tag)-2-save-focused")
        remote.press(.up)
        pause(0.9)
        note("\(tag)-3-back-explainer", "explainer=\(explainer(app))")
        XCTAssertTrue(isField(explainer(app)), "Up from Save Key must land back on the key field")
        remote.press(.menu)
        pause(1.5)
    }

    /// The TMDB Metadata Language page opened on the profile's stored value (read-only: Menu
    /// pops the page, nothing is selected). When that value is a language rather than Device,
    /// this is the "checked row far down the list" case without writing to the profile.
    func testTmdbLanguagePageOpensOnTheCheckedRow() throws {
        let app = try launch()
        try openPane(app, raw: "sources", index: Self.rootIndex["sources"]!, settingsTitle: "Settings", rowTitle: "Sources")
        _ = walk(app, to: "Metadata Language", max: 30)
        pause(0.6)
        note("wb-9-tmdb-row", "\(rowValue(app, "Metadata Language")) | focus: \(focusedNodes(app))")
        try requireRow(app, "Metadata Language")
        remote.press(.select)
        pause(2.5)
        shot("wb-9-tmdb-page-open")
        note("wb-9-tmdb-page-open-focus", focusedNodes(app))
        remote.press(.menu)
        pause(1.5)
        note("wb-9-tmdb-after-pop", "explainer=\(explainer(app))")
        remote.press(.menu)
        pause(1.5)
    }

    /// The deep-row case without touching the profile: `-debug.fallbackAudioSeed zu` (DEBUG seam in
    /// `SubtitlesAudioSettingsPane`) binds Fallback Audio Language to an in-memory Zulu, the LAST
    /// entry. The page must open with focus on Zulu; a pick from there (Up ×3) must come back as
    /// the row's value, and reopening must land on that pick. Nothing reaches the repository.
    func testFallbackAudioPageOpensOnADeepCheckedRow() throws {
        try deepRowEvidence(seed: "zu", seedLabel: "Zulu", tag: "wb-10")
    }

    /// Same, seeded in the middle of the list (English).
    func testFallbackAudioPageOpensOnAMidCheckedRow() throws {
        try deepRowEvidence(seed: "en", seedLabel: "English", tag: "wb-11")
    }

    /// Control for the deep-row leg: the page opened on None (in-memory seed ""), walked Down by
    /// hand to Zulu, then Up. Separates a List quirk at the end of the list from the page's claim.
    func testManualWalkToTheLastRow() throws {
        let app = try launch(extra: ["-debug.fallbackAudioSeed", ""])
        try openSubtitlesPane(app, settingsTitle: "Settings")
        _ = walk(app, to: "Fallback Audio Language")
        try requireRow(app, "Fallback Audio Language")
        remote.press(.select)
        pause(2.5)
        var log = ["page open: \(focusedNodes(app))"]
        press(.down, times: 85, gap: 0.3)
        pause(1.5)
        log.append("after 85 Down: \(focusedNodes(app))")
        shot("wb-12-manual-last-row")
        for step in 1...3 {
            remote.press(.up)
            pause(0.8)
            log.append("after Up \(step): \(focusedNodes(app))")
        }
        note("wb-12-manual-walk", log.joined(separator: "\n"))
        remote.press(.menu)
        pause(1.5)
        remote.press(.menu)
        pause(1.5)
    }

    private func deepRowEvidence(seed: String, seedLabel: String, tag: String) throws {
        let app = try launch(extra: ["-debug.fallbackAudioSeed", seed])
        try openSubtitlesPane(app, settingsTitle: "Settings")
        _ = walk(app, to: "Fallback Audio Language")
        pause(0.6)
        var log = ["row: \(rowValue(app, "Fallback Audio Language"))"]
        try requireRow(app, "Fallback Audio Language")
        // The seam must be live (a Release build has none): the row shows the seeded value, not
        // the profile's. Otherwise the pick below would write to the synced profile.
        guard rowValue(app, "Fallback Audio Language").contains(seedLabel) else {
            throw XCTSkip("the DEBUG seed is not live (row: \(rowValue(app, "Fallback Audio Language"))); not picking")
        }
        remote.press(.select)
        pause(2.5)
        shot("\(tag)-page-open-\(seed)")
        log.append("page open: \(focusedNodes(app))")
        for step in 1...3 {
            remote.press(.up)
            pause(0.8)
            log.append("after Up \(step): \(focusedNodes(app))")
        }
        shot("\(tag)c-after-3-up")
        try requirePageRow(app, pane: "subtitlesAudio", title: "Fallback Audio Language")
        remote.press(.select)   // in-memory only (the DEBUG seam)
        pause(2.0)
        log.append("row after pick: \(rowValue(app, "Fallback Audio Language")) explainer=\(explainer(app))")
        note("\(tag)-deep-page", log.joined(separator: "\n"))
        try requireRow(app, "Fallback Audio Language")
        remote.press(.select)
        pause(2.5)
        shot("\(tag)b-page-reopened")
        log.append("page reopened: \(focusedNodes(app))")
        note("\(tag)-deep-page", log.joined(separator: "\n"))
        remote.press(.menu)
        pause(1.5)
        remote.press(.menu)
        pause(1.5)
    }

    func testTmdbKeyRowsSplit() throws {
        try keySplitEvidence(category: "sources", tag: "wb-w7-tmdb") { $0 == "Personal API Key (Optional)" }
    }

    func testDebridKeyRowsSplit() throws {
        try keySplitEvidence(category: "services", tag: "wb-w7-debrid") { $0.hasPrefix("Or paste your") }
    }

    // MARK: French

    func testFrenchAudioPage() throws {
        let app = try launch(extra: ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"])
        try openSubtitlesPane(app, settingsTitle: "Paramètres")
        _ = walk(app, to: "Audio")
        pause(0.8)
        shot("wb-6-fr-pane")
        note("wb-6-fr-values", "focus: \(focusedNodes(app))")
        try requireRow(app, "Audio")
        remote.press(.select)
        pause(2.0)
        shot("wb-7-fr-audio-page-open")
        note("wb-7-fr-audio-page-open-focus", focusedNodes(app))
        press(.down, times: 12, gap: 0.35)
        pause(0.6)
        shot("wb-7b-fr-audio-page-scrolled")
        remote.press(.menu)
        pause(1.5)
        remote.press(.menu)
        pause(1.5)
    }


    /// Read-only: launches, records the profile picker's buttons, quits. Presses nothing.
    func testReadOnlyProfilePicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-home_layout", "classic", "-settings_style", "default"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        _ = chris.waitForExistence(timeout: 90)
        pause(2)
        note("wb-0-profile-picker-readonly", app.buttons.allElementsBoundByIndex.map(\.label).joined(separator: "\n"))
        shot("wb-0-profile-picker-readonly")
        app.terminate()
    }

}
