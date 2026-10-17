import XCTest

/// Perf review 2026-10-17, finding #1 (HomeView invalidation fan-out): how many `body` evaluations
/// one walk across a Classic Home row costs. Each Right rests 0.7 s, past the hero's 0.2 s focus
/// commit, so every step is a hero commit. Reads `debug_bodycounts` (`HomeBodyCounter`, DEBUG) before
/// and after the walk and attaches the deltas; the only assertion is that the walk happened.
///
/// Evidence, not a gate: run it on the commit before and after a change and compare the notes.
final class HomeBodyCountUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
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
        print("[HomeBodyCountUITests] \(name): \(text)")
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

    private static func counts(_ line: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, let value = Int(pair[1]) { out[String(pair[0])] = value }
        }
        return out
    }

    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func walk(extra: [String], name: String) throws {
        let app = launch(["-home_layout", "classic", "-home_upcoming_row_enabled", "NO",
                          "-inline_trailers_enabled", "NO", "-hero_trailer_autoplay", "NO",
                          "-sidebar_style", "tabs"] + extra)
        guard poll(30, step: 0.5, { !label(app, "debug_homeReturn").isEmpty }) else {
            throw HarnessAbort("debug_homeReturn never appeared (DEBUG build? -home_layout classic honoured?)")
        }
        // Down until a catalog row owns focus (past the hero CTA / Continue Watching).
        var owned = "-"
        for _ in 0..<5 {
            remote.press(.down)
            pause(1.8)
            owned = Self.token(label(app, "debug_homeReturn"), "own") ?? "-"
            if owned != "-", owned != "continue-watching" { break }
        }
        guard owned != "-" else { throw HarnessAbort("no row took focus: \(label(app, "debug_homeReturn"))") }
        pause(2.5)
        let before = label(app, "debug_bodycounts")
        let heroBefore = Self.token(label(app, "debug_hero"), "fitem") ?? "-"
        var commits = Set<String>()
        for _ in 0..<6 {
            remote.press(.right)
            pause(0.7)
            if let item = Self.token(label(app, "debug_hero"), "fitem"), item != "-" { commits.insert(item) }
        }
        pause(1.5)
        let after = label(app, "debug_bodycounts")
        let a = Self.counts(before), b = Self.counts(after)
        let delta = b.keys.sorted().map { "\($0)=\((b[$0] ?? 0) - (a[$0] ?? 0))" }.joined(separator: " ")
        note("\(name)_row", owned)
        note("\(name)_before", before)
        note("\(name)_after", after)
        note("\(name)_delta", "\(delta) heroCommits=\(commits.count) firstHero=\(heroBefore)")
        XCTAssertGreaterThanOrEqual(commits.count, 3, "the walk should commit the hero on most steps: \(commits)")
    }

    /// Classic container: the hero carousel scrolls with the rows.
    func testBodyCounts_ClassicRowWalk() throws {
        try walk(extra: ["-hero_nuvio_style", "NO"], name: "classic")
    }

    /// Pinned container (Nuvio-style hero above the rows).
    func testBodyCounts_PinnedRowWalk() throws {
        try walk(extra: ["-hero_nuvio_style", "YES"], name: "pinned")
    }
}
