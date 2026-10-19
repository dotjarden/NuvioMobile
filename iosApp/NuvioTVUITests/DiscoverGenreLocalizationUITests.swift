import XCTest

/// BUG-189 (Steven rc9): under `-AppleLanguages (fr)` the Discover grid's Genre pill reads the
/// localized genre, not Cinemeta's English manifest name. The oracle pairs the pill's label
/// (`discover.genrePicker`, the `PillLabel` title) with the grid readout's `genre=` token, which
/// stays the RAW manifest value (display-only mapping). The leg walks the genre menu until it
/// lands on a genre whose French name differs from the English one, then checks the pill no
/// longer shows the English name.
///
/// Needs the populated `Localizable.xcstrings` (fr) and the FA87 fixture (guest "Chris" with
/// Cinemeta enabled). Opens Discover from the rail (Rail navigation, Discover as its own tab), so
/// no localized tab title is needed. Helpers are this file's own (the harness's duplication rule).
final class DiscoverGenreLocalizationUITests: XCTestCase {

    let remote = XCUIRemote.shared

    /// Cinemeta genres whose French name does not contain the English one (Action, Crime,
    /// Romance … are spelled the same in French, so they make no oracle).
    private static let differsInFrench: Set<String> = [
        "Adventure", "Biography", "Comedy", "Drama", "Family", "Fantasy", "History", "Horror",
        "Mystery", "War",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private struct HarnessAbort: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = reason }
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
                               "-home_layout", "stage", "-discover_placement", "tab",
                               "-home_upcoming_row_enabled", "NO", "-inline_trailers_enabled", "NO",
                               "-sidebar_style", "rail", "-rail_visibility", "always"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the FA87 fixture set up?")
        remote.press(.left)
        pause(0.5)
        remote.press(.left)
        pause(0.5)
        remote.press(.select)
        pause(14)
        return app
    }

    private func label(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        return element.exists ? element.label : ""
    }

    private func gridLine(_ app: XCUIApplication) -> String { label(app, "discover_grid_state") }
    private func railState(_ app: XCUIApplication) -> String { label(app, "rail_state") }

    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0] == Substring(key) else { continue }
            return String(pair[1])
        }
        return nil
    }

    private func focusedFrames(_ app: XCUIApplication) -> [CGRect] {
        guard let root = try? app.snapshot() else { return [] }
        var out: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.hasFocus { out.append(node.frame) }
            node.children.forEach(walk)
        }
        walk(root)
        return out
    }

    /// A `Menu`'s focusable node is not the element carrying its identifier: match by centre.
    private func hasFocusByFrame(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus { return true }
        let a = element.frame
        return focusedFrames(app).contains { abs($0.midY - a.midY) < 12 && abs($0.midX - a.midX) < 40 }
    }

    /// Rail: Left until it expands, walk to the Discover item (id 6), select; wait for the grid.
    private func openDiscover(_ app: XCUIApplication) throws {
        for _ in 0..<15 where Self.token(railState(app), "expanded") != "1" {
            remote.press(.left)
            pause(0.5)
        }
        guard Self.token(railState(app), "expanded") == "1" else {
            throw HarnessAbort("the rail never opened from a Left walk — \(railState(app))")
        }
        for _ in 0..<8 where Int(Self.token(railState(app), "focused") ?? "") != 6 {
            let current = Int(Self.token(railState(app), "focused") ?? "") ?? -1
            remote.press(current == 0 || current == 1 ? .down : .up)
            pause(0.5)
        }
        guard Int(Self.token(railState(app), "focused") ?? "") == 6 else {
            throw HarnessAbort("the rail's focus never reached the Discover item — \(railState(app))")
        }
        remote.press(.select)
        let ready = poll(30, step: 0.5) {
            let line = gridLine(app)
            return Self.token(line, "state") == "loaded" && (Int(Self.token(line, "items") ?? "") ?? 0) >= 1
        }
        guard ready else { throw HarnessAbort("the Discover grid never settled: '\(gridLine(app))'") }
    }

    /// Walks the pill band Right then Left to the Genre pill; one Up between rounds in case focus
    /// sits in the grid (the band is the grid's top section).
    private func focusGenrePill(_ app: XCUIApplication, _ pill: XCUIElement) throws {
        for round in 0..<3 {
            if round > 0 { remote.press(.up); pause(0.7) }
            for direction in [XCUIRemote.Button.right, .left] {
                for _ in 0..<5 where !hasFocusByFrame(app, pill) {
                    remote.press(direction)
                    pause(0.6)
                }
            }
            if hasFocusByFrame(app, pill) { return }
        }
        throw HarnessAbort("focus never reached discover.genrePicker")
    }

    func testGenrePillReadsFrench() throws {
        let app = launch()
        try openDiscover(app)
        let pill = app.descendants(matching: .any)["discover.genrePicker"].firstMatch
        guard pill.waitForExistence(timeout: 6) else {
            throw XCTSkip("the selected catalog has no genre pill: '\(gridLine(app))'")
        }
        try focusGenrePill(app, pill)

        // Walk the menu one genre at a time until the raw genre is one French renames.
        var raw = Self.token(gridLine(app), "genre") ?? ""
        for _ in 0..<14 where !Self.differsInFrench.contains(raw) {
            remote.press(.select)        // open the menu on the current pick
            pause(1.0)
            remote.press(.down)
            pause(0.5)
            remote.press(.select)        // pick the next genre; the menu closes
            let before = raw
            _ = poll(10, step: 0.5) { (Self.token(gridLine(app), "genre") ?? "") != before }
            raw = Self.token(gridLine(app), "genre") ?? ""
            try focusGenrePill(app, pill)
        }
        guard Self.differsInFrench.contains(raw) else {
            throw HarnessAbort("never reached a genre French renames; last genre=\(raw) '\(gridLine(app))'")
        }
        let shown = pill.label
        print("[BUG189Leg] genre=\(raw) pill='\(shown)' grid='\(gridLine(app))'")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "bug189-fr-genre-pill"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(shown.isEmpty, "the genre pill has no label")
        XCTAssertFalse(shown.localizedCaseInsensitiveContains(raw),
                       "the genre pill still reads the English manifest name '\(raw)': '\(shown)'")
    }
}
