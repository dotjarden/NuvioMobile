import XCTest

/// Batch N (BUG-190 follow-up; Batch M pass: on the Classic rows collection page the focused row's
/// heading scrolled under the hero panel). The page now runs its rows in Classic Home's pinned mode
/// (reach band with the heading overlaid), so the engine's reveal brings the heading into view.
///
/// Oracle: frames only (XCUITest on the tvOS 27 sim never reports hasFocus). With focus moved Down to
/// the second row, a section heading (a static text carrying a source title) must exist with its
/// minY at or below the hero panel's maxY. The panel's maxY is the compact logo's maxY plus the
/// pinned hero height (`Theme.Size.heroCarouselHeightPinned`, 352 pt).
///
/// Fixture: as `FolderClassicHeroUITests` (FA87, guest "Chris" profile, one pinned collection with
/// two Cinemeta sources, seeded and cleared through `-debug.collectionsSeedJsonB64`).
///
/// Helpers are this file's own (the harness's duplication rule).
final class FolderClassicRowHeadingUITests: XCTestCase {

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
        print("[FolderClassicRowHeadingUITests] \(name): \(text)")
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

    // MARK: - Batch N (BUG-190 follow-up)

    /// The heroCarouselHeightPinned the page's panel is framed at.
    private static let heroPanelHeight: CGFloat = 352

    func testSecondRowHeadingSitsBelowTheHeroPanel() {
        let seed = Data(Self.seedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "classic", "-sidebar_style", "tabs",
                          "-folder_layout_default_classic", "rows", "-inline_trailers_enabled", "NO",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)

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

        let logo = app.descendants(matching: .any)["folder_classic_logo"].firstMatch
        XCTAssertTrue(logo.exists, "the compact folder logo is missing")
        let heroMaxY = logo.frame.maxY + Self.heroPanelHeight

        // A card in the first row holds focus (Down once if the page opened with focus elsewhere).
        if !poll(4, { Self.token(probe(app, "folder_classic_hero"), "fitem") != "-" }) {
            remote.press(.down)
            pause(1.5)
        }
        let firstItem = Self.token(probe(app, "folder_classic_hero"), "fitem")

        // Down to the second row; its focused card must differ from the first row's.
        remote.press(.down)
        let moved = poll(6) {
            let f = Self.token(probe(app, "folder_classic_hero"), "fitem")
            return f != nil && f != "-" && f != firstItem
        }
        pause(1.5)
        shot("row2-heading")
        XCTAssertTrue(moved, "Down never reached a card in the second row: \(probe(app, "folder_classic_hero"))")

        // Headings: static texts carrying a Cinemeta source title, at or below the panel's bottom edge.
        let screenHeight = app.windows.firstMatch.frame.height
        let titles = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "Popular", "Top", "Movie", "Series"))
        var below: [CGRect] = []
        for index in 0..<titles.count {
            let frame = titles.element(boundBy: index).frame
            if frame.minY >= heroMaxY - 1 && frame.maxY <= screenHeight { below.append(frame) }
        }
        note("row2-heading", "heroMaxY=\(heroMaxY) screenHeight=\(screenHeight) headingsBelow=\(below)")
        XCTAssertFalse(below.isEmpty,
                       "Batch N (BUG-190 follow-up): no row heading is visible below the hero panel (maxY \(heroMaxY)) with the second row focused")

        remote.press(.menu)
        pause(4)
        XCTAssertTrue(probe(app, "folder_classic_rows").hasSuffix("<absent>"), "Menu did not pop the folder")
    }
}
