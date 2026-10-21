import XCTest

/// Batch P Wave 2 (W2-5 a): how many `body` evaluations one Down press costs on the Stage strip.
/// Launches Stage in Rail mode (Corner, labels shown: Steven's rc10 chrome), lands on row 0, then
/// presses Down/Up 10 times (down to the last row, up, down), 1.8 s apart (past the 0.5 s glide and the counter's 0.5 s flush), and
/// reads `debug_bodycounts` (`HomeBodyCounter`, DEBUG) after each press. An idle window with no
/// press comes first, so a per-press delta can be told from background ticks.
///
/// Evidence, not a gate: the only assertion is that the strip paged. Run it before and after a
/// change and compare the attached `per_press` notes. Its helpers are its own (the harness rule).
final class StageBodyCountUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        // Review r1 P3-5: an evidence leg (70-140 s), not part of the default UI gate.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NUVIO_BODY_COUNT"] == "1",
                          "evidence leg: set NUVIO_BODY_COUNT=1 to run")
        continueAfterFailure = true
    }

    private struct HarnessAbort: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = reason }
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[StageBodyCountUITests] \(name): \(text)")
    }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

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

    private func label(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        return element.exists ? element.label : ""
    }

    private static func counts(_ line: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, let value = Int(pair[1]) { out[String(pair[0])] = value }
        }
        return out
    }

    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2, pair[0] == Substring(key) { return String(pair[1]) }
        }
        return nil
    }

    /// The views the report tracks, in print order.
    private static let tracked = ["StageStripHome", "StripPager", "StripPageSlot", "CatalogRowView",
                                  "CollectionRowView", "ContinueWatchingRow", "PinnedRowUpFallback",
                                  "InlineTrailerCard", "PosterCard", "HomeView"]

    private static func delta(_ a: [String: Int], _ b: [String: Int]) -> String {
        tracked.map { "\($0)=\((b[$0] ?? 0) - (a[$0] ?? 0))" }.joined(separator: " ")
    }

    private func walk(extra: [String], name: String) throws {
        let app = launch(["-home_layout", "stage", "-sidebar_style", "rail", "-rail_visibility", "always",
                          "-rail_position", "corner", "-rail_labels", "shown",
                          "-debug.homeScrollProbe", "YES", "-home_upcoming_row_enabled", "NO",
                          "-inline_trailers_enabled", "NO"] + extra)
        guard poll(30, step: 0.5, { !label(app, "debug_bodycounts").isEmpty && !label(app, "debug_strip").isEmpty }) else {
            throw HarnessAbort("debug_bodycounts/debug_strip never appeared (DEBUG build? -home_layout stage honoured?)")
        }
        // Rail mode lands focus on row 0's first card; if it did not, Down enters the strip.
        var stripLine = label(app, "debug_strip")
        for _ in 0..<3 where (Self.token(stripLine, "foc") ?? "-").hasPrefix("-") {
            remote.press(.down)
            pause(2.0)
            stripLine = label(app, "debug_strip")
        }
        note("\(name)_start_strip", stripLine)
        pause(3.0)
        // Idle control: the same read cadence, no press.
        let idleA = Self.counts(label(app, "debug_bodycounts"))
        pause(1.8)
        let idleB = Self.counts(label(app, "debug_bodycounts"))
        note("\(name)_idle", Self.delta(idleA, idleB))
        let startRow = Self.token(label(app, "debug_strip"), "row") ?? "?"
        var previous = idleB
        var lines: [String] = []
        var rows: [String] = [startRow]
        // The FA87 fixture has five rows (Continue Watching + four catalogs), so the walk goes down
        // to the last row, back up to row 0, and down again: ten presses that each page.
        let walk: [XCUIRemote.Button] = [.down, .down, .down, .down, .up, .up, .up, .up, .down, .down]
        for (press, button) in walk.enumerated() {
            remote.press(button)
            pause(1.8)
            let now = Self.counts(label(app, "debug_bodycounts"))
            let row = Self.token(label(app, "debug_strip"), "row") ?? "?"
            rows.append(row)
            lines.append("press \(press + 1) \(button == .down ? "D" : "U") row=\(row) \(Self.delta(previous, now))")
            previous = now
        }
        note("\(name)_per_press", lines.joined(separator: "\n"))
        note("\(name)_total", Self.delta(idleB, previous) + " rows=\(rows.joined(separator: ","))")
        let distinct = Set(rows.filter { $0 != "?" })
        XCTAssertGreaterThanOrEqual(distinct.count, 3, "the strip should page on Down: rows=\(rows)")
    }

    func testBodyCounts_StageDownWalk() throws {
        try walk(extra: [], name: "stage")
    }
}
