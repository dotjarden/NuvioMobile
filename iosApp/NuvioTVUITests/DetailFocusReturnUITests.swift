import XCTest

/// Batch M Wave 1 (BUG-187, Steven rc9: "back from a cast member, focus goes back to Play"): a
/// push off a Cast card or a More Like This card and Back must land on the same card, not on
/// Play. Reads the DEBUG `debug_detail_focus row=<row> idx=<key>` probe, mounted only under
/// `-debug.detailFocusProbe YES` (the tvOS 27 simulator never reports `hasFocus`): `row` is the
/// live focused row (`-` in the hero), `idx` the last card a tracked row remembered (the cast
/// index, or the More Like This item id).
///
/// Cast cards are links only with a TMDB id, so the fixture needs TMDB enrichment on; a title
/// with no tappable cast (or no More Like This) skips its leg rather than failing. Helpers are a
/// trimmed file-private copy, the `DetailScrollProbeTests` convention.
final class DetailFocusReturnUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    private func launchToDetail() -> XCUIApplication {
        let app = XCUIApplication()
        // Classic Home: the hero CTA route into Detail (`DetailScrollProbeTests.openDetailFromHomeHero`).
        app.launchArguments += ["-home_layout", "classic", "-debug.detailFocusProbe", "YES"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the sim session still signed in?")
        if !chris.hasFocus { press(.left, times: 3, gap: 0.5) }
        remote.press(.select)
        pause(10) // Home catalog fan-out
        press(.up, times: 6, gap: 0.5)
        press(.down, times: 1)
        pause(2)
        remote.press(.select)
        pause(6)
        var waited: TimeInterval = 0
        while !app.staticTexts["Cast"].exists, waited < 14 {
            pause(1)
            waited += 1
        }
        pause(2)
        return app
    }

    /// `debug_detail_focus`'s tokens, attached to the run log.
    private func probe(_ app: XCUIApplication, _ name: String) -> (row: String, idx: String) {
        let label = app.staticTexts["debug_detail_focus"]
        let text = label.waitForExistence(timeout: 4) ? label.label : "debug_detail_focus MISSING"
        let attachment = XCTAttachment(string: "\(name): \(text)")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[BUG187] \(name): \(text)")
        var tokens: [String: String] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { tokens[String(kv[0])] = String(kv[1]) }
        }
        return (tokens["row"] ?? "?", tokens["idx"] ?? "?")
    }

    /// Down until focus is in `row` (bounded); false when the page has no such focusable row.
    private func walkDown(to row: String, in app: XCUIApplication, maxPresses: Int = 16) -> Bool {
        for _ in 0..<maxPresses {
            if probe(app, "walk").row == row { return true }
            press(.down)
        }
        return probe(app, "walk end").row == row
    }

    // MARK: - Legs

    /// Detail → third cast card → person page → Back: the same cast card holds focus.
    func testBackFromCastMemberReturnsToTheCastCard() throws {
        let app = launchToDetail()
        guard walkDown(to: "cast", in: app) else {
            shot("187_no_cast")
            throw XCTSkip("no tappable cast row on this title (TMDB enrichment off?)")
        }
        press(.right, times: 2)
        let before = probe(app, "cast before push")
        XCTAssertEqual(before.row, "cast")
        shot("187_cast_before")
        remote.press(.select)
        pause(5)
        shot("187_person_page")
        remote.press(.menu)
        pause(3) // past the restore's last rung (1.1 s) and the engine's late restoration
        let after = probe(app, "cast after back")
        shot("187_cast_after")
        XCTAssertEqual(after.row, "cast", "Back from the person page left the Cast row (Play is row=-)")
        XCTAssertEqual(after.idx, before.idx, "Back from the person page landed on another cast card")
    }

    /// Detail → second More Like This card → its Detail → Back: the same card holds focus.
    func testBackFromMoreLikeThisReturnsToTheCard() throws {
        let app = launchToDetail()
        guard walkDown(to: "moreLikeThis", in: app, maxPresses: 20) else {
            shot("187_no_mlt")
            throw XCTSkip("no More Like This row on this title")
        }
        press(.right, times: 1)
        let before = probe(app, "mlt before push")
        XCTAssertEqual(before.row, "moreLikeThis")
        shot("187_mlt_before")
        remote.press(.select)
        pause(6)
        shot("187_mlt_pushed")
        remote.press(.menu)
        pause(3)
        let after = probe(app, "mlt after back")
        shot("187_mlt_after")
        XCTAssertEqual(after.row, "moreLikeThis", "Back from the pushed title left More Like This (Play is row=-)")
        XCTAssertEqual(after.idx, before.idx, "Back from the pushed title landed on another card")
    }

    /// BUG-194 (Batch P, P7): Back from a biography lands on the cast card in ONE move. The probe's
    /// `moves=` token (focus-row changes between the pop's appear and the release) arrives with the
    /// DetailView hunks; until they are applied it is absent and only the landing is asserted. The
    /// simulator never shows the engine's late restoration, so the device pass is the real check.
    func testBackFromCastMemberLandsInOneMove() throws {
        let app = launchToDetail()
        guard walkDown(to: "cast", in: app) else {
            shot("194_no_cast")
            throw XCTSkip("no tappable cast row on this title (TMDB enrichment off?)")
        }
        press(.right, times: 2)
        let before = probe(app, "194 cast before push")
        XCTAssertEqual(before.row, "cast")
        remote.press(.select)
        pause(5)
        remote.press(.menu)
        pause(3)
        let label = app.staticTexts["debug_detail_focus"]
        let text = label.waitForExistence(timeout: 4) ? label.label : ""
        let after = probe(app, "194 cast after back")
        XCTAssertEqual(after.row, "cast")
        XCTAssertEqual(after.idx, before.idx)
        if let range = text.range(of: "moves=") {
            let digits = text[range.upperBound...].prefix { $0.isNumber }
            XCTAssertLessThanOrEqual(Int(digits) ?? 99, 1, "Back from the biography moved focus more than once: \(text)")
        }
    }
}
