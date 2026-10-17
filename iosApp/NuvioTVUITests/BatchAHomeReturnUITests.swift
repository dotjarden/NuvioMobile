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

    // MARK: - Batch B (BUG-156 (a) + (b), Steven's rc4 verdict 2026-10-16)

    /// Stage Home: down to row ≥ 1, Right twice. Returns the `debug_strip` line there.
    private func walkStageStrip(_ app: XCUIApplication) throws -> String {
        guard poll(30, step: 0.5, { !label(app, "debug_strip").isEmpty }) else {
            throw HarnessAbort("debug_strip never appeared (DEBUG build? -home_layout stage honoured?)")
        }
        remote.press(.down)
        pause(2.0)
        var reached = Self.token(label(app, "debug_strip"), "row").flatMap { Int($0) } ?? 0
        for _ in 0..<2 {
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
        return label(app, "debug_strip")
    }

    /// `label`'s whole line every 0.1 s for `seconds` (one read per tick, so tokens stay paired).
    private func sampleLines(_ app: XCUIApplication, _ identifier: String, seconds: TimeInterval) -> [String] {
        var lines: [String] = []
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            lines.append(label(app, identifier))
            pause(0.1)
        }
        return lines
    }

    /// `values` with consecutive repeats collapsed.
    private static func changes(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in if result.last != value { result.append(value) } }
    }

    /// `label`'s `key` token every 0.1 s for `seconds` (the restore's moves, which a single read misses).
    private func sample(_ app: XCUIApplication, _ identifier: String, _ key: String, seconds: TimeInterval) -> [String] {
        var values: [String] = []
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let value = Self.token(label(app, identifier), key) ?? "?"
            if values.last != value { values.append(value) }
            pause(0.1)
        }
        return values
    }

    /// Leg 3 (BUG-156 (a)): Stage Home, the focus engine's late restoration simulated. The simulator's
    /// engine never steals focus after a pop the way the Apple TV's does (0.55–0.98 s late, Batch A
    /// device pass step 8), so `-debug.uncoverStealMs 600` sends focus to the previous row 0.6 s after
    /// the restore lands. With no viewer input since the pop the strip must re-grab its row and card
    /// (`[StageStrip] restore regrab … since=landing`).
    func testBatchB_StagePopRegrabsAfterALateSteal() throws {
        let app = launch(Self.arguments(layout: "stage") + ["-debug.uncoverStealMs", "600"])
        let before = try walkStageStrip(app)
        let row = Self.token(before, "row")
        let foc = Self.token(before, "foc")
        note("steal_before", before)
        remote.press(.select)
        pause(5.0)
        remote.press(.menu)
        let lines = sampleLines(app, "debug_strip", seconds: 4.0)
        let rows = Self.changes(lines.map { Self.token($0, "row") ?? "?" })
        // B13: the strip may not page to the stolen row on the way (the visible detour Steven saw).
        let pages = Self.changes(lines.map { Self.token($0, "page") ?? "?" })
        pause(1.0)
        let after = label(app, "debug_strip")
        note("steal_after", "\(after) rows=\(rows) pages=\(pages)")
        XCTAssertEqual(pages, [Self.token(before, "page") ?? "?"],
                       "the strip paged away during the re-grab (BUG-156 double move): pages=\(pages)")
        shot("steal_after_pop")
        XCTAssertEqual(app.state, .runningForeground)
        // B13: the landed restore gates every other row, so the steal may never land at all; either
        // way the strip ends on its row and card, and never pages away (below).
        XCTAssertEqual(Self.token(after, "row"), row, "the re-grab must bring the strip back to its row: \(after) rows=\(rows)")
        XCTAssertEqual(Self.token(after, "foc"), foc, "and to the card the push left from: \(after)")
    }

    /// Leg 4 (BUG-156 (a)): Stage Home, the viewer's own Down right after the restore lands is theirs.
    /// Before, any row change inside the window re-grabbed; now the press is stamped by the
    /// viewer-input clock and retires the restore (`restore retired … why=viewer input=down`).
    func testBatchB_StageViewerDownAfterPopIsNotPulledBack() throws {
        let app = launch(Self.arguments(layout: "stage"))
        let before = try walkStageStrip(app)
        guard let row = Self.token(before, "row").flatMap(Int.init) else { throw HarnessAbort("no row= on debug_strip: \(before)") }
        remote.press(.select)
        pause(5.0)
        remote.press(.menu)
        // `debug_strip row=` keeps its last value under the push, so it cannot show the landing;
        // the simulator's restore lands 0.3–0.6 s after the pop (the steal leg's samples). A Down
        // 1.0 s after the Menu is inside the 1.5 s window from the landing.
        pause(1.0)
        XCTAssertEqual(Self.token(label(app, "debug_strip"), "row"), String(row),
                       "the pop must be back on row \(row) before the Down: \(label(app, "debug_strip"))")
        remote.press(.down)
        let rows = sample(app, "debug_strip", "row", seconds: 3.0)
        let after = label(app, "debug_strip")
        note("viewer_after", "\(after) rows=\(rows)")
        XCTAssertEqual(Self.token(after, "row"), String(row + 1),
                       "the viewer's Down must stand: the restore may not pull the strip back to row \(row): \(rows)")
        XCTAssertFalse(rows.drop(while: { $0 != String(row + 1) }).contains(String(row)),
                       "the strip went back to row \(row) after the viewer's Down: \(rows)")
    }

    // MARK: - Folder ← Detail (BUG-156 (b))

    /// One pinned collection, one folder over three Cinemeta catalogs (three strip rows).
    private static let folderSeedJson = """
    [{"id":"zzbatchb-collection","title":"ZZBatchB","pinToTop":true,"showAllTab":true,"folders":[{"id":"zzbatchb-folder","title":"ZZBatchBFolder","hideTitle":false,"heroBackdropUrl":"https://images.metahub.space/background/medium/tt0111161/img","coverImageUrl":"https://images.metahub.space/poster/medium/tt0111161/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"top"},{"provider":"addon","addonId":"com.linvo.cinemeta","type":"series","catalogId":"top"},{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"imdbRating"}]}]}]
    """

    private func clearSeed() {
        let app = XCUIApplication()
        app.launchArguments = ["-debug.collectionsSeedJsonB64", Data("[]".utf8).base64EncodedString()]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        if chris.waitForExistence(timeout: 90) {
            remote.press(.left)
            pause(0.5)
            remote.press(.left)
            pause(0.5)
            remote.press(.select)
        }
        pause(8)
        app.terminate()
    }

    private func detailPageUp(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["detail_hero"].exists
            || ["Mark Watched", "Watched", "Add to Library", "In Library"].contains { app.buttons[$0].exists }
    }

    /// Leg 5 (BUG-156 (b), Steven: "the view jumps back up" after Back from a movie inside a
    /// collection): Stage folder page, row 1 card 2 → Detail → Menu: the folder strip is back on row
    /// 1 and the same card (`folder_rows_state row= foc=`), and the pop went through the folder's own
    /// restore (`[StageStrip] restore … reason=uncover source=folder`). `steal`: the engine's late
    /// restoration simulated (`-debug.uncoverStealMs`), which the folder page must re-grab too.
    private func runFolderPop(steal: Bool) throws {
        let seed = Data(Self.folderSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        var arguments = Self.arguments(layout: "stage") + ["-debug.collectionsSeedJsonB64", seed, "-folder_layout_grid", ""]
        if steal { arguments += ["-debug.uncoverStealMs", "600"] }
        let app = launch(arguments)
        guard poll(30, step: 0.5, { !label(app, "debug_strip").isEmpty }) else {
            throw HarnessAbort("debug_strip never appeared")
        }
        // The pinned collection is the strip's first row; its folder tile is the first card.
        let folderId = "nuvio-folder://zzbatchb-collection/zzbatchb-folder"
        var onFolder = false
        for _ in 0..<4 where !onFolder {
            remote.press(.down)
            onFolder = poll(2.0) { Self.token(label(app, "debug_stage"), "fitem") == folderId }
        }
        guard onFolder else {
            throw XCTSkip("the seeded folder tile never took focus (debug_stage: \(label(app, "debug_stage"))) — the collections seed is refused on a signed-in account")
        }
        remote.press(.select)
        guard poll(15, step: 0.5, {
            let line = label(app, "folder_rows_state")
            return Self.token(line, "state") == "rows" && Self.token(line, "row") == "0"
        }) else {
            throw HarnessAbort("the folder Rows page never settled on row 0: \(label(app, "folder_rows_state"))")
        }
        pause(1.0)
        remote.press(.down)
        pause(2.5)
        remote.press(.right)
        pause(2.0)
        let before = label(app, "folder_rows_state")
        let row = Self.token(before, "row")
        let foc = Self.token(before, "foc")
        note("folder_before", before)
        XCTAssertEqual(row, "1", "Down must page to row 1: \(before)")
        XCTAssertNotEqual(foc, "-", "the folder strip must record the focused card: \(before)")
        remote.press(.select)
        guard poll(20, step: 0.5, { self.detailPageUp(app) }) else {
            XCTFail("Select on a folder card did not open its Detail page")
            return
        }
        pause(2.0)
        shot("folder_detail")
        remote.press(.menu)
        let rows = sample(app, "folder_rows_state", "row", seconds: 4.0)
        pause(1.0)
        let after = label(app, "folder_rows_state")
        note("folder_after", "\(after) rows=\(rows)")
        shot("folder_after_pop")
        XCTAssertEqual(app.state, .runningForeground, "one Menu from Detail must pop to the folder, never leave the app")
        // B13: the landed restore gates every other row, so a steal may never land; either way the
        // strip must end on its row and card.
        _ = steal
        XCTAssertEqual(Self.token(after, "row"), row, "back from Detail the folder strip must be on the row it left: \(after) rows=\(rows)")
        XCTAssertEqual(Self.token(after, "foc"), foc, "and on the card it left: \(after)")
    }

    func testBatchB_FolderPopRestoresRowAndCard() throws {
        try runFolderPop(steal: false)
    }

    func testBatchB_FolderPopRegrabsAfterALateSteal() throws {
        try runFolderPop(steal: true)
    }

    // MARK: - Classic: folder page, Menu back, then Up (perf #1 home split, device pass 2026-10-17)

    /// Device regression on the Home split (Living Room ATV, Test 2, Classic, hero on): Down to a
    /// collection's folder tile, Select (folder page), Menu back (focus restored on the tile), then
    /// Up. Expected: focus moves to the row above (Continue Watching here; the guest fixture follows
    /// no show, so there is no Upcoming row). The regression sent it into the hero CTA with the rows
    /// left scrolled down. Oracle: `debug_homeReturn own=` after the Up.
    ///
    /// `_Pinned` (Nuvio-style hero) is the folder-return Up-skip leg (2026-10-17). It failed 3/3 on
    /// the base before the fix: Continue Watching could not take focus after the pop, the BUG-112
    /// ladder's writes to it were dropped and its last rung handed focus to the hero CTA. Fixed by
    /// `HomeView.remountTopRowsAfterPop`.
    private func runClassicFolderPopThenUp(nuvioStyle: Bool) throws {
        let seed = Data(Self.folderSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let arguments = Self.arguments(layout: "classic")
            + ["-debug.collectionsSeedJsonB64", seed, "-folder_layout_default", "grid",
               "-hero_nuvio_style", nuvioStyle ? "YES" : "NO",
               // `[HomeScrollProbe] upFallback` / `[HomeReturn]` lines in the console for a failure.
               "-debug.homeScrollProbe", "YES"]
        let app = launch(arguments)
        guard poll(30, step: 0.5, { !label(app, "debug_homeReturn").isEmpty }) else {
            throw HarnessAbort("debug_homeReturn never appeared (DEBUG build? -home_layout classic honoured?)")
        }
        let collectionKey = "zzbatchb-collection"
        var owned: [String] = []
        var onFolder = false
        for _ in 0..<6 where !onFolder {
            remote.press(.down)
            pause(1.8)
            let own = Self.token(label(app, "debug_homeReturn"), "own") ?? "-"
            if owned.last != own { owned.append(own) }
            onFolder = own == collectionKey
        }
        guard onFolder else {
            throw XCTSkip("the seeded collection row never took focus (rows=\(owned) \(label(app, "debug_homeReturn"))) — the collections seed is refused on a signed-in account")
        }
        let above = owned.dropLast().last(where: { $0 != "-" })
        note("classic_folder_rows", "\(owned) above=\(above ?? "-")")
        remote.press(.select)
        pause(5.0)
        shot("classic_folder_page")
        XCTAssertTrue(label(app, "debug_homeReturn").contains("own=-") || !app.descendants(matching: .any)["debug_hero"].isHittable,
                      "Select on the folder tile should open the folder page")
        remote.press(.menu)
        let restored = poll(5.0) { Self.token(label(app, "debug_homeReturn"), "own") == collectionKey }
        pause(2.0)
        note("classic_folder_after_pop", label(app, "debug_homeReturn"))
        XCTAssertTrue(restored, "the pop must restore focus to the folder tile: \(label(app, "debug_homeReturn"))")
        remote.press(.up)
        pause(2.5)
        let afterUp = label(app, "debug_homeReturn")
        let hero = label(app, "debug_hero")
        note("classic_folder_after_up", "\(afterUp) | \(hero) | upfallback=\(label(app, "debug_upfallback"))")
        shot("classic_folder_after_up")
        XCTAssertEqual(Self.token(afterUp, "own"), above,
                       "Up from the restored folder tile must reach the row above (\(above ?? "-")), not the hero: \(afterUp) | \(hero)")
        XCTAssertEqual(Self.token(hero, "foc"), "0", "the hero CTA must not take focus: \(hero)")
    }

    /// Folder-return Up-skip (2026-10-17): the same class from a Detail push lower down. Down to the
    /// third row under Continue Watching, Select (Detail), Menu back, then Up once per row: every Up
    /// must reach the row above it, and the last must reach Continue Watching, never the hero CTA.
    /// Rows kept alive offscreen through a push and pop came back unable to take focus.
    func testBatchC_ClassicDetailPopThenUpWalk_Pinned() throws {
        let seed = Data(Self.folderSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let arguments = Self.arguments(layout: "classic")
            + ["-debug.collectionsSeedJsonB64", seed, "-folder_layout_default", "grid",
               "-hero_nuvio_style", "YES", "-debug.homeScrollProbe", "YES"]
        let app = launch(arguments)
        guard poll(30, step: 0.5, { !label(app, "debug_homeReturn").isEmpty }) else {
            throw HarnessAbort("debug_homeReturn never appeared (DEBUG build? -home_layout classic honoured?)")
        }
        var owned: [String] = []
        for _ in 0..<4 {
            remote.press(.down)
            pause(1.8)
            let own = Self.token(label(app, "debug_homeReturn"), "own") ?? "-"
            if own != "-", owned.last != own { owned.append(own) }
        }
        note("detail_walk_rows", "\(owned)")
        guard owned.count >= 3, owned.first == "continue-watching", let origin = owned.last else {
            throw XCTSkip("the fixture did not give three rows under Continue Watching: \(owned)")
        }
        remote.press(.select)
        guard poll(20, step: 0.5, { self.detailPageUp(app) }) else {
            throw HarnessAbort("Select on a catalog card did not open its Detail page")
        }
        pause(2.0)
        remote.press(.menu)
        let restored = poll(5.0) { Self.token(label(app, "debug_homeReturn"), "own") == origin }
        pause(2.0)
        note("detail_walk_after_pop", label(app, "debug_homeReturn"))
        XCTAssertTrue(restored, "the pop must restore focus to \(origin): \(label(app, "debug_homeReturn"))")
        for expected in owned.dropLast().reversed() {
            remote.press(.up)
            pause(2.5)
            let afterUp = label(app, "debug_homeReturn")
            let hero = label(app, "debug_hero")
            note("detail_walk_up_to_\(expected)", "\(afterUp) | \(hero) | upfallback=\(label(app, "debug_upfallback"))")
            XCTAssertEqual(Self.token(afterUp, "own"), expected,
                           "Up must reach \(expected), not the hero: \(afterUp) | \(hero)")
            if Self.token(afterUp, "own") != expected { shot("detail_walk_miss_\(expected)"); break }
        }
    }

    func testBatchC_ClassicFolderPopThenUp_InScroll() throws {
        try runClassicFolderPopThenUp(nuvioStyle: false)
    }

    func testBatchC_ClassicFolderPopThenUp_Pinned() throws {
        try runClassicFolderPopThenUp(nuvioStyle: true)
    }
}
