import XCTest

/// BUG-156 (P2; Steven, beta.19-rc3 follow-ups 2026-10-09 and 10-14: "Home doesn't come back to where
/// I was after a collection"): after a push from a Home row pops, focus is back on the same row and the
/// same card, in both Home layouts. The FA87 guest fixture has no collections, so the push is a title →
/// Detail (the same `homePath` edge a folder page uses; the restore never looks at what was pushed).
///
/// Oracles (DEBUG readouts, never frames):
///   - Stage: `debug_strip … row=<index> key=<rowKey> foc=<rowKey>/<itemId>` (`foc` moves on every card
///     the strip's memory records, so a wrong landing changes it);
///   - Classic: `debug_homeReturn own=<rowKey> foc=<rowKey>/<itemId> ret=<last restore event>`
///     (HomeView.swift, fed by each row's own `@FocusState`; `own` is the row holding focus NOW, so a
///     pop that lands on the hero CTA reads `own=-` even though `foc` still names the old card).
///
/// Helpers are this file's own (the harness's duplication rule).
final class BatchAHomeReturnUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private struct HarnessAbort: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = reason }
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

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
        print("[BatchAHomeReturnUITests] \(name): \(text)")
    }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    /// Fresh launch, then the profile gate ("Chris" is the first profile), then `settle`.
    @discardableResult
    private func launch(_ arguments: [String], settle: TimeInterval = 14) -> XCUIApplication {
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

    private func label(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        return element.exists ? element.label : ""
    }

    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0] == Substring(key) else { continue }
            return String(pair[1])
        }
        return nil
    }

    /// The row half of a `foc=<rowKey>/<itemId>` token. Row keys never contain "/" at the start, but
    /// item ids can (`nuvio-folder://…`), so split on the FIRST slash only.
    private static func row(ofFoc foc: String?) -> String? {
        guard let foc, foc != "-", let slash = foc.firstIndex(of: "/") else { return nil }
        return String(foc[..<slash])
    }

    /// Common launch flags: no Upcoming row (the guest follows no show), no In Row trailers (a morph
    /// widens cards), Tabs chrome so a stored rail choice cannot change what Down from the bar reaches.
    private static func arguments(layout: String) -> [String] {
        ["-home_layout", layout, "-debug.homeScrollProbe", "YES", "-home_upcoming_row_enabled", "NO",
         "-inline_trailers_enabled", "NO", "-sidebar_style", "tabs"]
    }

    // MARK: - Stage

    /// Leg 1: Stage. Down to row 3, Right twice, Select (Detail), Menu: the strip is back on row 3 and
    /// its memory names the same card (`[StageStrip] restore … reason=uncover` in the console).
    func testBatchA_StagePopRestoresRowAndCard() throws {
        let app = launch(Self.arguments(layout: "stage"))
        guard poll(30, step: 0.5, { !label(app, "debug_strip").isEmpty }) else {
            throw HarnessAbort("debug_strip never appeared (DEBUG build? -home_layout stage honoured?)")
        }
        // Tabs mode: launch focus is on the tab bar; the first Down enters row 0.
        remote.press(.down)
        pause(2.0)
        var reached = Self.token(label(app, "debug_strip"), "row").flatMap { Int($0) } ?? 0
        for _ in 0..<3 {
            let before = reached
            remote.press(.down)
            pause(2.0)
            reached = Self.token(label(app, "debug_strip"), "row").flatMap { Int($0) } ?? before
            if reached == before { break }
        }
        guard reached >= 1 else { throw HarnessAbort("the strip never left row 0: \(label(app, "debug_strip"))") }
        remote.press(.right)
        pause(1.0)
        remote.press(.right)
        pause(1.5)
        let before = label(app, "debug_strip")
        let row = Self.token(before, "row")
        let foc = Self.token(before, "foc")
        note("stage_before", before)
        XCTAssertNotNil(foc, "no foc= on debug_strip: \(before)")
        remote.press(.select)
        pause(5.0)
        shot("stage_detail")
        remote.press(.menu)
        let restored = poll(4.0) {
            let line = label(app, "debug_strip")
            return Self.token(line, "row") == row && Self.token(line, "foc") == foc
        }
        pause(1.5)
        let after = label(app, "debug_strip")
        note("stage_after", after)
        shot("stage_after_pop")
        XCTAssertEqual(app.state, .runningForeground, "one Menu from Detail must pop, never leave the app")
        XCTAssertTrue(restored, "the pop must land on row \(row ?? "-") card \(foc ?? "-"): before=\(before) after=\(after)")
        XCTAssertEqual(Self.token(after, "row"), row, "and stay there: \(after)")
        XCTAssertEqual(Self.token(after, "foc"), foc, "and stay on that card: \(after)")
    }

    // MARK: - Classic

    /// Leg 2: Classic. The same walk through the Classic rows: down three rows, Right twice, Select
    /// (Detail), Menu: `debug_homeReturn foc=` names the same row and card again.
    func testBatchA_ClassicPopRestoresRowAndCard() throws {
        let app = launch(Self.arguments(layout: "classic"))
        guard poll(30, step: 0.5, { !label(app, "debug_homeReturn").isEmpty }) else {
            throw HarnessAbort("debug_homeReturn never appeared (DEBUG build? -home_layout classic honoured?)")
        }
        // Down from the tab bar reaches the hero CTA (Show Hero on) or the first row; keep going until
        // the remembered row has changed three times after the first row (row 3), or Down stops moving.
        var rows: [String] = []
        for _ in 0..<8 where rows.count < 4 {
            remote.press(.down)
            pause(1.8)
            if let current = Self.row(ofFoc: Self.token(label(app, "debug_homeReturn"), "foc")),
               rows.last != current {
                rows.append(current)
            }
        }
        guard rows.count >= 2 else {
            throw HarnessAbort("Classic rows never took focus: \(label(app, "debug_homeReturn")) rows=\(rows)")
        }
        remote.press(.right)
        pause(1.0)
        remote.press(.right)
        pause(1.5)
        let before = label(app, "debug_homeReturn")
        let foc = Self.token(before, "foc")
        note("classic_before", "\(before) rows=\(rows)")
        remote.press(.select)
        pause(5.0)
        shot("classic_detail")
        remote.press(.menu)
        let ownRow = Self.row(ofFoc: foc)
        let restored = poll(4.0) {
            let line = label(app, "debug_homeReturn")
            return Self.token(line, "foc") == foc && Self.token(line, "own") == ownRow
        }
        pause(1.5)
        let after = label(app, "debug_homeReturn")
        note("classic_after", after)
        shot("classic_after_pop")
        XCTAssertEqual(app.state, .runningForeground, "one Menu from Detail must pop, never leave the app")
        XCTAssertTrue(restored, "the pop must land on \(foc ?? "-"): before=\(before) after=\(after)")
        XCTAssertEqual(Self.token(after, "foc"), foc, "and stay on that card: \(after)")
        XCTAssertEqual(Self.token(after, "own"), ownRow, "focus must be IN that row, not on the hero: \(after)")
        // `ret=` names the restore's last event: a push line, then `restore … landed=` (native
        // restoration already right) or a rung that moved focus back.
        XCTAssertNotEqual(Self.token(after, "ret"), "-", "the push edge never logged an origin: \(after)")
    }
}
