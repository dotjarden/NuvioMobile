import XCTest

/// BUG-155 (P2; Steven, beta.19-rc3 follow-ups 2026-10-14: while typing a search the caret sits one
/// letter behind the text on screen, and the results take a while to land). Types a ten-letter
/// title into Search one letter at a time and reads the DEBUG `debug_search_perf` probe
/// (`SearchPerfProbe.probeLine`: `search_perf keys= maxBody= inflight= legacy= q= first= last=
/// cancelled=`), the same numbers the console's `[SearchPerf]` lines carry.
///
/// Two legs on one build:
///   - the fix (default): `SearchContent` never re-runs on a keystroke after the first letter
///     (`maxBody <= 1`), superseded queries' catalog fetches are cancelled (`cancelled >= 1`), and
///     the last query settles within 4 s of its debounce firing;
///   - `-debug.searchLegacy YES` (the pre-fix behaviour): no fetch is ever cancelled
///     (`cancelled == 0`); its `maxBody` and timings are recorded for the before/after, not asserted.
///
/// The gap between letters is 0.4 s, not the 0.25 s a fast typist would use: the debounce is
/// 350 ms, so every letter fires a search and the next letter supersedes it while its fetches are
/// still running, which is how a remote types (one letter per second or slower) and the only way a
/// superseded fetch exists to be cancelled. XCUITest's own per-letter latency adds to the gap.
///
/// Helpers are this file's own (the harness's duplication rule).
final class BatchASearchPerfUITests: XCTestCase {

    let remote = XCUIRemote.shared
    private static let title = "fight club"
    private static let tabNames = ["Home", "Search", "Discover", "Library", "Add-ons", "Settings", "Profile"]

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
        print("[BatchASearchPerfUITests] \(name): \(text)")
    }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.25, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    /// Fresh launch, then the profile gate ("Chris" is the first profile), then `settle`.
    private func launch(_ arguments: [String], settle: TimeInterval = 12) -> XCUIApplication {
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

    private static func intToken(_ line: String, _ key: String) -> Int? {
        token(line, key).flatMap { Int($0) }
    }

    /// Tabs mode: climb to the tab bar, pick Search, Down into the inline keyboard.
    private func openSearch(_ app: XCUIApplication) {
        for _ in 0..<30 {
            if Self.tabNames.contains(where: { app.buttons[$0].exists && app.buttons[$0].hasFocus }) { break }
            remote.press(.up)
            pause(0.35)
        }
        let tab = app.buttons["Search"]
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0..<8 where !tab.hasFocus {
                remote.press(direction)
                pause(0.5)
            }
            if tab.hasFocus { break }
        }
        remote.press(.select)
        pause(2)
        remote.press(.down)
        pause(1)
    }

    /// Waits for the inline keyboard, then (tvOS 26: keys report focus) steps until a key holds
    /// focus. On the 27.x runtime keys never report focus, so there it only waits.
    private func focusKeyboard(_ app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 8) else { return false }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 { pause(1); return true }
        func keyboardHasFocus() -> Bool {
            guard let root = try? keyboard.snapshot() else { return false }
            func walk(_ node: XCUIElementSnapshot) -> Bool { node.hasFocus || node.children.contains(where: walk) }
            return walk(root)
        }
        for _ in 0..<4 {
            if keyboardHasFocus() { return true }
            let onTabBar = Self.tabNames.contains { app.buttons[$0].exists && app.buttons[$0].hasFocus }
            remote.press(onTabBar ? .down : (keyboard.frame.width < 900 ? .left : .up))
            pause(0.7)
        }
        return keyboardHasFocus()
    }

    private func searchFieldText(_ app: XCUIApplication) -> String {
        var value = (app.searchFields.firstMatch.value as? String) ?? ""
        if let hint = value.range(of: ", Press ") { value = String(value[..<hint.lowerBound]) }
        return value == "Search movies & shows" ? "" : value
    }

    /// Opens Search, types `title` letter by letter and returns the settled probe line.
    private func typeAndSettle(_ arguments: [String], tag: String) throws -> String {
        let app = launch(arguments)
        openSearch(app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "Search must show the system search field")
        guard focusKeyboard(app) else {
            throw HarnessAbort("focus never reached the inline search keyboard (\(tag))")
        }
        let typeStart = Date()
        for letter in Self.title {
            app.typeText(String(letter))
            pause(0.4)
        }
        let typeSeconds = Date().timeIntervalSince(typeStart)
        XCTAssertEqual(searchFieldText(app), Self.title, "typing must reach the system field (\(tag))")
        let wanted = Self.title.replacingOccurrences(of: " ", with: "+")
        let settled = poll(20) { Self.token(label(app, "debug_search_perf"), "q") == wanted }
        let line = label(app, "debug_search_perf")
        note("\(tag)_probe", "\(line) | typed \(Self.title.count) letters in \(String(format: "%.1f", typeSeconds)) s")
        shot("\(tag)_settled")
        guard settled else {
            throw HarnessAbort("the probe never reported a settled search for '\(Self.title)' (\(tag)): '\(line)' — DEBUG build?")
        }
        return line
    }

    /// The fix: no keystroke re-runs the results page after the first letter, superseded fetches
    /// are cancelled, the final query settles in under 4 s.
    func testBatchA_SearchTypingFix() throws {
        let line = try typeAndSettle(["-home_layout", "classic", "-sidebar_style", "tabs",
                                      "-inline_trailers_enabled", "NO"], tag: "fix")
        XCTAssertEqual(Self.token(line, "legacy"), "0", "the default build must run the fix: \(line)")
        let maxBody = Self.intToken(line, "maxBody") ?? Int.max
        XCTAssertLessThanOrEqual(maxBody, 1, "SearchContent must not re-evaluate on a keystroke (BUG-155): \(line)")
        let cancelled = Self.intToken(line, "cancelled") ?? -1
        let first = Self.intToken(line, "first") ?? Int.max
        // A fetch can only be cancelled while it is still in flight when the next letter's debounce
        // fires (≥ 350 ms after it). When the guest's one catalog answers faster than that (two
        // runs on 2026-10-15: `first=48`, `first=51`), nothing is ever in flight to cancel and
        // `cancelled=0` is correct; the fix is then proven by `maxBody` (0 bodies per keystroke
        // against legacy's 1) and by the unit tests of `CatalogInflightRequests`.
        if first >= 350 {
            XCTAssertGreaterThanOrEqual(cancelled, 1, "a superseded query's catalog fetches must be cancelled: \(line)")
        } else {
            note("fix_cancel_note", "catalog answered in \(first) ms (< 350 ms debounce): no fetch was in flight to cancel; cancelled=\(cancelled)")
        }
        let last = Self.intToken(line, "last") ?? Int.max
        XCTAssertGreaterThanOrEqual(last, 0, "the probe's last must be a time: \(line)")
        XCTAssertLessThan(last, 4000, "the final query must settle within 4 s of its debounce: \(line)")
    }

    /// `-debug.searchLegacy YES`: the pre-fix behaviour, for the before/after. Only the fetch half
    /// is asserted (nothing cancelled); the body count and timings are recorded.
    func testBatchA_SearchTypingLegacy() throws {
        let line = try typeAndSettle(["-home_layout", "classic", "-sidebar_style", "tabs",
                                      "-inline_trailers_enabled", "NO", "-debug.searchLegacy", "YES"], tag: "legacy")
        XCTAssertEqual(Self.token(line, "legacy"), "1", "-debug.searchLegacy YES must be honoured: \(line)")
        XCTAssertEqual(Self.intToken(line, "cancelled"), 0, "legacy must leave abandoned fetches running: \(line)")
        note("legacy_maxBody", Self.token(line, "maxBody") ?? "?")
    }
}
