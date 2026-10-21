import XCTest

/// Wave 3b (GitHub #10 BUG-215, #9 BUG-201): screenshot harness for the Settings pane clip check
/// and the subtitle colour swatch focus walk. Not a pass/fail leg: each test opens one surface,
/// focuses a row, writes a PNG to `docs/research/wave3b-sim-2026-10-21/` (and attaches it to the
/// result bundle as a backup) and records which node holds focus. It asserts only that it got
/// there. FA87 fixture (tvOS 26.5, `hasFocus` works).
final class Wave3bSettingsEvidenceTests: XCTestCase {

    let remote = XCUIRemote.shared

    private static let outDir = "/Users/christianturnbull/Claude/Projects/Nuvio tvOS/docs/research/wave3b-sim-2026-10-21"
    /// Root order and raw values (match `NuvioTVUITests.settingsRootOrder`).
    private static let rootOrder = ["accountProfiles", "services", "appearance", "homeScreen", "detailPage",
                                    "player", "sources", "subtitlesAudio", "about", "developer"]

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

    /// Every node that reports focus, from ONE snapshot: identifier, label, frame.
    private func focusedNodes(_ app: XCUIApplication) -> String {
        guard let root = try? app.snapshot() else { return "(no snapshot)" }
        var out: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.hasFocus {
                out.append("id=<\(node.identifier)> label=<\(node.label)> type=\(node.elementType.rawValue) frame=\(node.frame)")
            }
            node.children.forEach(walk)
        }
        walk(root)
        return out.isEmpty ? "(nothing reports focus)" : out.joined(separator: "\n")
    }

    @discardableResult
    private func launch(settingsStyle: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-home_layout", "classic", "-settings_style", settingsStyle]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists {
            press(.left, times: 2, gap: 0.5)
            remote.press(.select)
        }
        pause(10)
        return app
    }

    /// Settings tab, root list showing, focus parked on the first category.
    private func openSettingsRoot(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        press(.up, times: 6, gap: 0.4)
        for _ in 0..<8 where !(settings.exists && settings.hasFocus) {
            remote.press(.right)
            pause(0.5)
        }
        remote.press(.select)
        pause(3)
        press(.up, times: 12, gap: 0.3)
        press(.down)
        pause(1)
    }

    /// Walks the root to `category` and pushes it. Returns whether the pane appeared.
    @discardableResult
    private func openPane(_ app: XCUIApplication, _ category: String) -> Bool {
        let index = Self.rootOrder.firstIndex(of: category)!
        press(.down, times: index, gap: 0.7)
        pause(0.8)
        remote.press(.select)
        pause(2.5)
        return app.descendants(matching: .any)["settings_pane_\(category)"].waitForExistence(timeout: 6)
    }

    // MARK: BUG-215 — does the focused row clip at the List's left edge?

    private func clipEvidence(style: String, tag: String) {
        let app = launch(settingsStyle: style)
        openSettingsRoot(app)
        // Root: focus the Sources row (so a focused row is on screen), shoot.
        press(.down, times: 6, gap: 0.7)
        pause(1)
        shot("\(tag)-root-\(style)")
        note("\(tag)-root-\(style)-focus", focusedNodes(app))
        // Pane: push Sources.
        remote.press(.select)
        pause(2.5)
        XCTAssertTrue(app.descendants(matching: .any)["settings_pane_sources"].waitForExistence(timeout: 6), "Sources pane never opened")
        pause(1)
        shot("\(tag)-sources-\(style)-row1")
        note("\(tag)-sources-\(style)-row1-focus", focusedNodes(app))
        press(.down, times: 2, gap: 0.8)
        shot("\(tag)-sources-\(style)-row3")
        note("\(tag)-sources-\(style)-row3-focus", focusedNodes(app))
        press(.down, times: 3, gap: 0.8)
        shot("\(tag)-sources-\(style)-row6")
        note("\(tag)-sources-\(style)-row6-focus", focusedNodes(app))
        remote.press(.menu)
        pause(1.5)
    }

    func testClipDefault() { clipEvidence(style: "default", tag: "w9") }

    func testClipMinimal() { clipEvidence(style: "minimal", tag: "w9") }

    // MARK: BUG-201 — subtitle swatch focus walk, and are the four swatches separate targets?

    func testSubtitleSwatchWalk() {
        let app = launch(settingsStyle: "default")
        openSettingsRoot(app)
        XCTAssertTrue(openPane(app, "subtitlesAudio"), "Subtitles pane never opened")
        pause(1)
        shot("w5-subtitles-landing")
        note("w5-subtitles-landing-focus", focusedNodes(app))
        // Walk to the Text Color row: Down until the explainer reads "Text Color".
        let title = app.staticTexts["settings_explainer_title"]
        for _ in 0..<6 where !(title.exists && title.label == "Text Color") {
            remote.press(.down)
            pause(0.8)
        }
        note("w5-explainer-title", title.exists ? title.label : "(no explainer title)")
        shot("w5-swatch-1-focused-selected")
        note("w5-swatch-1-focus", focusedNodes(app))
        for step in 2...4 {
            remote.press(.right)
            pause(0.8)
            shot("w5-swatch-\(step)-focused")
            note("w5-swatch-\(step)-focus", focusedNodes(app))
        }
        // Back to the first (selected) swatch, then off the row to see the selected swatch at rest.
        press(.left, times: 3, gap: 0.6)
        press(.down, gap: 0.8)
        shot("w5-swatch-rest-selected")
        note("w5-swatch-rest-focus", focusedNodes(app))
        remote.press(.menu)
        pause(1.5)
    }
}
