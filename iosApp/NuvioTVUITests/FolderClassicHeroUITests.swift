import XCTest

/// BUG-190 (Steven rc9: FEAT-79's Classic rows page inside a collection showed no title poster and
/// no synopsis, only the collection art). Classic Home with Collections Layout = Rows opens a folder
/// as one Classic row per source under the folder's compact logo, and the focused card now drives a
/// Classic Home "Show Hero OFF" panel (D5): its backdrop and its synopsis.
///
/// Oracle: the DEBUG `folder_classic_hero fitem=<focused card id|-> pitem=<presented identity|->
/// pbd=<0|1>` readout. The leg asserts the panel commits the focused card, follows a Right to the
/// next card, and keeps a title while focus moves around. Screenshots `hero-1-first-card` and
/// `hero-2-next-card` are the visual check (the Edit band must not overlap the logo or the panel).
///
/// Fixture: FA87, guest "Chris" profile with Cinemeta. One pinned collection, one folder, two
/// Cinemeta sources, seeded through the guest-only `-debug.collectionsSeedJsonB64` knob (BUG-38's
/// recipe) and cleared with `"[]"` afterwards.
///
/// Helpers are this file's own (the harness's duplication rule).
final class FolderClassicHeroUITests: XCTestCase {

    let remote = XCUIRemote.shared

    private static let seedJson = """
    [{"id":"zzhero-collection","title":"ZZHero","pinToTop":true,"showAllTab":true,"folders":[{"id":"zzhero-folder","title":"ZZHeroFolder","hideTitle":false,"coverImageUrl":"https://images.metahub.space/poster/medium/tt0111161/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"top"},{"provider":"addon","addonId":"com.linvo.cinemeta","type":"series","catalogId":"top"}]}]}]
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
        print("[FolderClassicHeroUITests] \(name): \(text)")
    }

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
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
        return app
    }

    private func clearSeed() {
        let app = launch(["-debug.collectionsSeedJsonB64", Data("[]".utf8).base64EncodedString()])
        pause(8)
        app.terminate()
    }

    private func probe(_ app: XCUIApplication, _ id: String) -> String {
        let element = app.descendants(matching: .any)[id].firstMatch
        return element.exists ? element.label : "\(id) <absent>"
    }

    /// The label of the element holding focus (tvOS 26.5 reports `hasFocus`; 27.0 never does).
    private func focusedLabel(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.label : "<none>"
    }

    /// `key=value` out of a readout line, matched on the exact key.
    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0] == Substring(key) else { continue }
            return String(pair[1])
        }
        return nil
    }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    // MARK: - BUG-190

    func testClassicRowsFolderShowsTheFocusedTitlesHero() {
        let seed = Data(Self.seedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "classic", "-sidebar_style", "tabs",
                          "-folder_layout_default_classic", "rows", "-inline_trailers_enabled", "NO",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)

        // Into the pinned folder tile on Classic Home, then open it.
        var onTile = false
        for _ in 0..<8 where !onTile {
            if focusedLabel(app).contains("ZZHero") { onTile = true; break }
            remote.press(.down)
            pause(2)
        }
        XCTAssertTrue(onTile || focusedLabel(app).contains("ZZHero"), "the folder tile never took focus on Classic Home")
        remote.press(.select)
        pause(8)
        XCTAssertFalse(probe(app, "folder_classic_rows").hasSuffix("<absent>"), "the Classic rows page did not open")
        XCTAssertFalse(probe(app, "folder_classic_logo").hasSuffix("<absent>"), "the compact folder logo is missing")

        // A card in the first row holds focus (Down once if the page opened with focus elsewhere).
        if !poll(4, { Self.token(probe(app, "folder_classic_hero"), "fitem") != "-" }) {
            remote.press(.down)
            pause(1.5)
        }
        let committed = poll(6) {
            let line = probe(app, "folder_classic_hero")
            return Self.token(line, "fitem") != "-" && Self.token(line, "pitem") != "-"
        }
        let first = probe(app, "folder_classic_hero")
        note("hero-1-first-card", "focus=\(focusedLabel(app))\n\(first)")
        shot("hero-1-first-card")
        XCTAssertTrue(committed, "BUG-190: the focused card never reached the hero panel: \(first)")
        let firstItem = Self.token(first, "fitem")
        if let pitem = Self.token(first, "pitem"), let firstItem {
            XCTAssertTrue(pitem.hasSuffix(":\(firstItem)"), "the panel presents the focused card: \(first)")
        }

        // Right: the panel follows the next card.
        remote.press(.right)
        let followed = poll(5) {
            let line = probe(app, "folder_classic_hero")
            guard let f = Self.token(line, "fitem"), let p = Self.token(line, "pitem") else { return false }
            return f != firstItem && f != "-" && p.hasSuffix(":\(f)")
        }
        let second = probe(app, "folder_classic_hero")
        note("hero-2-next-card", "focus=\(focusedLabel(app))\n\(second)")
        shot("hero-2-next-card")
        XCTAssertTrue(followed, "BUG-190: the panel did not follow the focused card: \(second)")

        // Menu pops back to Home.
        remote.press(.menu)
        pause(4)
        XCTAssertTrue(probe(app, "folder_classic_rows").hasSuffix("<absent>"), "Menu did not pop the folder")
    }
}
