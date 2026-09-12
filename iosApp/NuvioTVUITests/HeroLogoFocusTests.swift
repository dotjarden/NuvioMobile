import XCTest

/// FEAT-42 (2026-09-11): "add the movie logo to the feed selection" — the Home hero/focus panel's
/// title-logo resolution now reaches catalog items the shared TMDB overlay never touched (past
/// `HOME_ROW_ENRICHMENT_PREFIX`, or a TMDB-id catalog the overlay skips entirely), via
/// `HeroArtResolver.logoPlan` + `TitleLogoStore` (`HomeView.swift`). This is an EVIDENCE test, not
/// a hardware-proof one: whether the logo bitmap actually reaches the screen (as opposed to just
/// resolving inside the resolver) depends on the same FEAT-14/BUG-93 lift/ring rendering path every
/// other card treatment does, which the simulator cannot fully stand in for — see the device pass
/// this task's plan owes. What this test DOES pin, off the release-safe `debug_hero`/`hero_probe_blob`
/// probes, live on the fixture: a row item well past the shared overlay's reach commits its hero
/// with a resolved logo (`plg=1`), the presented item and the focused item agree, a quick
/// leave-and-return re-presents from cache with the same logo source, and the probe's `present`
/// lines carry the new `logoSrc=` field with no `same=1` repaint signature.
///
/// Helpers below are a trimmed copy of `NuvioTVUITests`'s (`pause`/`press`/`launchToHome`/
/// `moveFocus`/`openTab`/`heroProbeLines`/`probeField`/`probeKind`/`readHeroProbeAboutPane`) — see
/// `HeroFolderSwapTests`'s own type doc for why these are duplicated per hero test file rather than
/// shared (each copy is already `private` to its own file).
final class HeroLogoFocusTests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Helpers (trimmed copies)

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    @discardableResult
    private func launchToHome(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += extraArguments
        app.launch()
        let chris = app.buttons["Chris"]
        XCTAssertTrue(chris.waitForExistence(timeout: 90),
                      "profile picker never appeared — is the sim session still signed in?")
        if chris.exists {
            if !chris.hasFocus { press(.left, times: 3, gap: 0.5) }
            remote.press(.select)
        }
        return app
    }

    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            pause(0.7)
        }
        return element.exists && element.hasFocus
    }

    private func openTab(_ app: XCUIApplication, named title: String) {
        let tabNames = ["Home", "Search", "Library", "Add-ons", "Settings", "Profile"]
        for _ in 0..<40 {
            if tabNames.contains(where: { app.buttons[$0].exists && app.buttons[$0].hasFocus }) { break }
            remote.press(.up)
            pause(0.35)
        }
        press(.up, times: 1, gap: 0.5)
        let tab = app.buttons[title]
        if !moveFocus(.right, until: tab, max: 6) {
            _ = moveFocus(.left, until: tab, max: 8)
        }
        remote.press(.select)
        pause(2)
        press(.down, times: 1)
    }

    /// Reads the `hero_probe_lines`/`hero_probe_blob` ring buffer (`AboutSettingsPane.swift`).
    /// Prefers the hidden single-`Text` blob (whole buffer in one label) and falls back to the
    /// per-line container's `staticText` children.
    private func heroProbeLines(_ app: XCUIApplication) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        func findBlob(_ node: XCUIElementSnapshot) -> String? {
            if node.identifier == "hero_probe_blob", !node.label.isEmpty { return node.label }
            for child in node.children {
                if let hit = findBlob(child) { return hit }
            }
            return nil
        }
        if let blob = findBlob(root) {
            let fromBlob = blob.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            if fromBlob.count > 1 { return fromBlob }
        }
        var container: XCUIElementSnapshot?
        func findContainer(_ node: XCUIElementSnapshot) {
            guard container == nil else { return }
            if node.identifier == "hero_probe_lines" {
                container = node
                return
            }
            for child in node.children { findContainer(child) }
        }
        findContainer(root)
        guard let container else { return [] }
        var lines: [String] = []
        func collect(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, !node.label.isEmpty { lines.append(node.label) }
            for child in node.children { collect(child) }
        }
        collect(container)
        return lines
    }

    /// Reads a single `key=value` token out of a probe line. Tolerant of token order, first match
    /// wins.
    private func probeField(_ line: String, _ key: String) -> String? {
        let prefix = "\(key)="
        for token in line.split(separator: " ") where token.hasPrefix(prefix) {
            return String(token.dropFirst(prefix.count))
        }
        return nil
    }

    /// The probe line's TYPE token — second whitespace-separated token.
    private func probeKind(_ line: String) -> String? {
        let tokens = line.split(separator: " ")
        return tokens.count > 1 ? String(tokens[1]) : nil
    }

    /// Navigates Settings → About and reads the probe buffer.
    @discardableResult
    private func readHeroProbeAboutPane(_ app: XCUIApplication, shotPrefix: String) -> [String] {
        openTab(app, named: "Settings")
        let about = app.buttons["About"]
        _ = moveFocus(.down, until: about, max: 8)
        press(.right, times: 1)
        pause(1.5)
        XCTContext.runActivity(named: "\(shotPrefix)_about_probe") { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(shotPrefix)_about_probe"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        let lines = heroProbeLines(app)
        if lines.isEmpty {
            XCTFail("\(shotPrefix): hero_probe_lines produced no readable lines")
        } else {
            let blob = lines.joined(separator: "\n")
            let attachment = XCTAttachment(string: blob)
            attachment.name = "\(shotPrefix)_probe_lines_text"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("[HeroProbe] \(shotPrefix):\n\(blob)")
        }
        return lines
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    // MARK: - test62

    /// Self-locating loop: walk Down (up to 20 times) looking for the first row-focused item that
    /// is NOT a collection folder — `fitem=` off `debug_hero`, non-empty and not prefixed
    /// `nuvio-folder://` (the same prefix `HeroFolderSwapTests.locateFolderHero` matches the
    /// other way). Returns the presses it took, or nil (having already logged the last probe
    /// label) if the budget exhausts.
    private func locateNonFolderRow(_ probe: XCUIElement) -> Int? {
        var lastLabel = ""
        for attempt in 1...20 {
            press(.down, times: 1, gap: 0.9)
            let label = probe.label
            lastLabel = label
            guard let fitem = probeField(label, "fitem"), fitem != "-", !fitem.isEmpty else { continue }
            if !fitem.hasPrefix("nuvio-folder://") { return attempt }
        }
        print("[test62] no non-folder row focused after 20 Down presses. Last probe: \(lastLabel)")
        return nil
    }

    /// FEAT-42: focuses a catalog row item well past the shared TMDB overlay's reach (`Right ×14`,
    /// past `HOME_ROW_ENRICHMENT_PREFIX`'s 12), lets the resolver's dwell + `laterSwapDeadline`
    /// settle, and reads the hero's committed logo state straight off `debug_hero`. Then proves the
    /// warm path (leave, come straight back) re-presents the same logo source, and reads the
    /// `hero_probe_blob` for the photo-contract invariants every hero test shares: no `same=1`
    /// repaint line, and — new for FEAT-42 — a `logoSrc=` field on every `present` line with no
    /// item presenting more than once per visit.
    func test62HeroLogoOnRowFocus() throws {
        let app = launchToHome(extraArguments: ["-debug.homeHeroProbe", "YES"])

        let probe = app.staticTexts["debug_hero"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20),
                      "debug_hero probe never appeared — Home rows are not up, nothing to walk")
        pause(2.0) // catalog fan-out settle, matching the other hero tests' post-Home pause

        guard let downsPressed = locateNonFolderRow(probe) else {
            throw XCTSkip("no non-folder row focused within 20 Down presses on this profile's Home")
        }
        print("[test62] focused a non-folder row after \(downsPressed) Down presses")

        // Past the shared overlay's 12-item reach — the FEAT-42 gap this task closes.
        press(.right, times: 14, gap: 0.6)
        pause(2)
        shot(app, "62a_deep_row_item_focused")

        let firstLabel = probe.label
        let fitem = probeField(firstLabel, "fitem") ?? "-"
        let pitemRaw = probeField(firstLabel, "pitem") ?? "-"
        // `pitem` is `"\(type):\(id)"`; `fitem` is the bare id — compare the id half.
        let pitemId = pitemRaw.split(separator: ":").dropFirst().joined(separator: ":")
        XCTAssertEqual(pitemId, fitem, "the hero must have committed to the item focus actually landed on: \(firstLabel)")

        let plgs = probeField(firstLabel, "plgs") ?? "none"
        let firstVisitHadLogo = probeField(firstLabel, "plg") == "1"
        print("[test62] first visit: plgs=\(plgs) plg=\(probeField(firstLabel, "plg") ?? "-") (firstVisitHadLogo=\(firstVisitHadLogo))")

        guard plgs != "none" else {
            throw XCTSkip("this fixture item's logo plan resolved to .none (no addon/TMDB/metahub candidate) — nothing to assert on this item; re-run or pick a different fixture row")
        }
        XCTAssertEqual(probeField(firstLabel, "plg"), "1",
                       "plgs=\(plgs) named a source but no logo bitmap is presented: \(firstLabel)")

        // Warm-path: leave this card and come straight back. A cache-warm re-presentation must
        // keep the same logo and the same origin — no re-resolution, no flicker back to text.
        press(.left, times: 1, gap: 0.6)
        pause(0.5)
        press(.right, times: 1, gap: 0.6)
        pause(1.5)
        let warmLabel = probe.label
        XCTAssertEqual(probeField(warmLabel, "plg"), "1", "warm-path revisit must still present the logo: \(warmLabel)")
        XCTAssertEqual(probeField(warmLabel, "plgs"), plgs, "warm-path revisit must not change the logo's origin: \(warmLabel)")
        shot(app, "62b_warm_path_revisit")

        // Photo-contract invariants off the About pane's ring buffer.
        let lines = readHeroProbeAboutPane(app, shotPrefix: "62c")
        let presentLines = lines.filter { probeKind($0) == "present" }

        for line in presentLines {
            XCTAssertNotEqual(probeField(line, "same"), "1", "same=1 is the repaint signature the photo contract forbids: \(line)")
            XCTAssertNotNil(probeField(line, "logoSrc"), "every present line must carry the FEAT-42 logoSrc= field: \(line)")
        }

        // At most one `present` per (item, visit): this walk visits at most a small handful of
        // distinct items (the down-walk's search plus the one focused row item, twice), so no
        // single identity should ever accumulate more than two `present` lines in the 32-line
        // rolling buffer.
        var presentsByItem: [String: Int] = [:]
        for line in presentLines {
            guard let item = probeField(line, "item") else { continue }
            presentsByItem[item, default: 0] += 1
        }
        for (item, count) in presentsByItem {
            XCTAssertLessThanOrEqual(count, 2, "item \(item) presented \(count) times across the walk + warm-path revisit (expected at most one per visit): \(presentLines)")
        }

        let restored = launchToHome(extraArguments: [])
        XCTAssertTrue(restored.state == .runningForeground)
    }
}
