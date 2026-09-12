import XCTest

/// FEAT-42 (2026-09-11): "add the movie logo to the feed selection" — the Home hero/focus panel's
/// title-logo resolution now reaches catalog items the shared TMDB overlay never touched (past
/// `HOME_ROW_ENRICHMENT_PREFIX`, or a TMDB-id catalog the overlay skips entirely), via
/// `HeroArtResolver.logoPlan` + `TitleLogoStore` (`HomeView.swift`). This is an EVIDENCE test, not
/// a hardware-proof one: whether the logo bitmap actually reaches the screen (as opposed to just
/// resolving inside the resolver) depends on the same FEAT-14/BUG-93 lift/ring rendering path every
/// other card treatment does, which the simulator cannot fully stand in for — see the device pass
/// this task's plan owes. What this test DOES pin, off the release-safe `debug_hero`/`hero_probe_blob`
/// probes, live on the fixture: at least one card in a row walk presents its logo FROM THE STORE
/// (`plgs=tmdb plg=1`) — the one reading FEAT-42 alone can produce — the presented item and the
/// focused item agree, `plgs` and `plg` never disagree about whether a bitmap is on screen, a quick
/// leave-and-return still presents a logo, and the probe's `present` lines carry the `logoSrc=`
/// field with no `same=1` repaint signature and no back-to-back commit of one item.
///
/// rc12 (Codex Finding B) rewrote the walk: the first version accepted a pre-existing
/// addon/metahub logo as success and SKIPPED when a card presented none, so no failure of the
/// store, `.pending` or prewarm path could make it fail. It now walks a row out and back (and a
/// second row if the first yields nothing) and FAILS with the collected `(fitem, plgs, plg)` table,
/// with a single explicit `-debug.assumeTmdbOff` runner escape hatch.
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

    /// A single settled read of `debug_hero` for one focused card: which item focus is on, what the
    /// hero committed for it, and which of `logoPlan`'s four sources the PRESENTED logo came from.
    private struct LogoRead: CustomStringConvertible {
        let pass: String
        let step: Int
        let fitem: String
        let pitem: String
        let plgs: String
        let plg: String

        /// The FEAT-42 store path — the one source that only exists because `TitleLogoStore` was
        /// consulted (an addon logo, a metahub guess and "nothing" all predate this task).
        var provesTheStorePath: Bool { plgs == "tmdb" && plg == "1" }
        var description: String { "\(pass)\(step) \(fitem) plgs=\(plgs) plg=\(plg)" }
    }

    /// The FEAT-42 sources a card may legitimately present, in the order `logoPlan` tries them.
    private static let logoSources = ["addon", "tmdb", "metahub"]

    /// How far along a row to walk. `HOME_ROW_ENRICHMENT_PREFIX` is 12 (the shared TMDB overlay's
    /// reach) and `CatalogRowView.homePreviewLimit` is 18 (what the row renders, and what the
    /// FEAT-42 first-focus prewarm batches a lookup for), so a 16-card walk covers the whole gap
    /// this task closes while staying inside the prewarmed prefix. KEEP IN SYNC with both.
    private static let cardsPerRow = 16

    /// The ONE escape hatch. A fixture with TMDB genuinely switched off (no key, artwork off) can
    /// never produce `plgs=tmdb`, and on such a run this test has nothing to prove rather than
    /// something to report — but that has to be asserted from OUTSIDE, never inferred from the
    /// absence of the very evidence the test exists to find (the mistake the first version of this
    /// test made: it skipped on `plgs=none`, so a broken store/pending integration passed silently).
    /// Set it on the RUNNER, not the app: `-debug.assumeTmdbOff` in the runner's own arguments, or
    /// `TEST_RUNNER_NUVIO_ASSUME_TMDB_OFF=1` in the xcodebuild environment (the `TEST_RUNNER_`
    /// prefix is stripped before it reaches the runner's environment). Defaults off.
    private var assumeTmdbOff: Bool {
        if ProcessInfo.processInfo.arguments.contains("-debug.assumeTmdbOff") { return true }
        let environment = ProcessInfo.processInfo.environment
        for key in ["NUVIO_ASSUME_TMDB_OFF", "TEST_RUNNER_NUVIO_ASSUME_TMDB_OFF"] {
            if let value = environment[key], ["1", "YES", "yes", "true"].contains(value) { return true }
        }
        return false
    }

    private func readLogo(_ probe: XCUIElement, pass: String, step: Int) -> LogoRead {
        let label = probe.label
        return LogoRead(pass: pass, step: step,
                        fitem: probeField(label, "fitem") ?? "-",
                        pitem: probeField(label, "pitem") ?? "-",
                        plgs: probeField(label, "plgs") ?? "-",
                        plg: probeField(label, "plg") ?? "-")
    }

    /// Walks `direction` across one row, one card at a time, reading `debug_hero` after each hop has
    /// had time to settle (the 0.2 s focus dwell plus the resolver's 400 ms `laterSwapDeadline`).
    /// Stops early at the end of the row (two consecutive reads of the same item — a press into the
    /// row's edge is a no-op) or as soon as one card proves the store path. Returns the reads it
    /// collected.
    private func walkRow(_ probe: XCUIElement, direction: XCUIRemote.Button, pass: String,
                         steps: Int) -> [LogoRead] {
        var reads: [LogoRead] = []
        for step in 1...steps {
            press(direction, times: 1, gap: 0.85)
            let read = readLogo(probe, pass: pass, step: step)
            reads.append(read)
            if read.provesTheStorePath { break }
            if reads.count >= 2, reads[reads.count - 2].fitem == read.fitem {
                // Row edge: the press moved nothing, so every further press in this direction is
                // another no-op. (Two reads of one item is also the warm re-read, which is fine —
                // it just means there is nothing new to learn this way.)
                break
            }
        }
        return reads
    }

    // MARK: - test62


    /// Self-locating loop: walk Down (up to 20 times) looking for the first row-focused item that
    /// is NOT a collection folder — `fitem=` off `debug_hero`, non-empty and not prefixed
    /// `nuvio-folder://` (the same prefix `HeroFolderSwapTests.locateFolderHero` matches the
    /// other way). Returns the presses it took, or nil (having already logged the last probe
    /// label) if the budget exhausts.
    ///
    /// `avoiding` is the item the caller has just finished with: a single Down press can be read
    /// before the destination row has published its own focus (the departing row's revert grace),
    /// so the second row search must not accept the card it is trying to leave.
    private func locateNonFolderRow(_ probe: XCUIElement, avoiding: String? = nil) -> Int? {
        var lastLabel = ""
        for attempt in 1...20 {
            press(.down, times: 1, gap: 0.9)
            let label = probe.label
            lastLabel = label
            guard let fitem = probeField(label, "fitem"), fitem != "-", !fitem.isEmpty else { continue }
            if let avoiding, fitem == avoiding { continue }
            if !fitem.hasPrefix("nuvio-folder://") { return attempt }
        }
        print("[test62] no non-folder row focused after 20 Down presses. Last probe: \(lastLabel)")
        return nil
    }

    /// FEAT-42: proves the `TitleLogoStore` path actually reaches the Home hero, on the fixture, off
    /// the release-safe probes.
    ///
    /// The PROOF is `plgs=tmdb` with `plg=1` on at least one card: `addon` predates this task (the
    /// item's own logo field), `metahub` predates it too (BUG-17's synthesized guess), and `none` is
    /// the absence of evidence — so `tmdb` is the only reading that can only happen because
    /// `logoPlan` consulted the store. The walk therefore does not settle for one card: it steps
    /// along the row one card at a time, recording `(fitem, plgs, plg)` for each, and when the
    /// forward pass finds nothing it walks back over the same cards, because a card whose first
    /// visit read `none` has kicked `repairMetahubMiss` on the way (a metahub guess that 404s is
    /// exactly what makes the store the better answer next time) and a second visit is where that
    /// repair shows up as `tmdb`. If a whole row yields nothing it tries one more row before
    /// failing, and it FAILS with the collected table rather than skipping — an empty walk is either
    /// a broken store/pending integration or a row of titles TMDB has no logo for, and both of those
    /// are findings, not reasons to pass quietly. The only skip is an explicit
    /// `-debug.assumeTmdbOff` on the runner (see `assumeTmdbOff`).
    ///
    /// Why the first version of this test did not do its job (Codex Finding B, rc12): it accepted an
    /// `addon`/`metahub` reading as success and SKIPPED on `plgs=none`, so nothing in the store,
    /// pending or prewarm path could fail it; and its warm-path leg asserted the origin was
    /// UNCHANGED on the revisit, which rejects the metahub→tmdb upgrade the repair path is built to
    /// perform.
    ///
    /// This stays an EVIDENCE test, not a hardware-proof one: whether the resolved bitmap reaches
    /// the panel the way it should on a TV rides the same FEAT-14/BUG-93 rendering path the
    /// simulator cannot stand in for — see the device pass this task's plan owes.
    func test62HeroLogoOnRowFocus() throws {
        let app = launchToHome(extraArguments: ["-debug.homeHeroProbe", "YES"])

        let probe = app.staticTexts["debug_hero"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20),
                      "debug_hero probe never appeared — Home rows are not up, nothing to walk")
        pause(2.0) // catalog fan-out settle, matching the other hero tests' post-Home pause

        var reads: [LogoRead] = []
        var proof: LogoRead?
        var rowsWalked = 0

        rowSearch: for rowAttempt in 1...2 {
            guard let downsPressed = locateNonFolderRow(probe, avoiding: reads.last?.fitem) else {
                if rowAttempt == 1 {
                    throw XCTSkip("no non-folder row focused within 20 Down presses on this profile's Home")
                }
                break rowSearch
            }
            rowsWalked += 1
            print("[test62] row \(rowAttempt): non-folder row focused after \(downsPressed) Down presses")

            // Out along the row, past the shared overlay's 12-item reach — the FEAT-42 gap.
            let forward = walkRow(probe, direction: .right, pass: "r\(rowAttempt)>", steps: Self.cardsPerRow)
            reads += forward
            if rowAttempt == 1 { shot(app, "62a_deep_row_item_focused") }

            // The hero must be showing the card focus actually settled on. `pitem` is `"type:id"`,
            // `fitem` the bare id.
            if let settled = forward.last {
                let pitemId = settled.pitem.split(separator: ":").dropFirst().joined(separator: ":")
                XCTAssertEqual(pitemId, settled.fitem,
                               "the hero must have committed to the item focus landed on: \(settled)")
            }
            if let hit = forward.first(where: { $0.provesTheStorePath }) {
                proof = hit
                break rowSearch
            }

            // Back over the same cards: the revisit where a repaired metahub miss becomes `tmdb`.
            let back = walkRow(probe, direction: .left, pass: "r\(rowAttempt)<", steps: forward.count)
            reads += back
            if let hit = back.first(where: { $0.provesTheStorePath }) {
                proof = hit
                break rowSearch
            }
        }

        let table = reads.map(\.description).joined(separator: "\n")
        let tableAttachment = XCTAttachment(string: "rows walked: \(rowsWalked)\n\(table)")
        tableAttachment.name = "62_logo_reads"
        tableAttachment.lifetime = .keepAlways
        add(tableAttachment)
        print("[test62] \(reads.count) reads across \(rowsWalked) row(s):\n\(table)")

        // `presentedLogoSource` and `presented.logo` are set in one transaction and may never
        // disagree (see `presentedLogoSource`'s doc comment): a named source means a bitmap is on
        // screen, and `none` means the text wordmark is.
        for read in reads where read.fitem != "-" {
            if Self.logoSources.contains(read.plgs) {
                XCTAssertEqual(read.plg, "1", "plgs named \(read.plgs) but no logo bitmap is presented: \(read)")
            } else if read.plgs == "none" {
                XCTAssertEqual(read.plg, "0", "plgs=none but a logo bitmap is presented: \(read)")
            }
        }

        guard let proof else {
            if assumeTmdbOff {
                throw XCTSkip("""
                -debug.assumeTmdbOff: this run declares TMDB switched off, so TitleLogoStore can \
                never resolve a URL and plgs=tmdb is unreachable by construction. \
                \(reads.count) reads, none from the store.
                """)
            }
            XCTFail("""
            FEAT-42: no card presented a logo from TitleLogoStore. \(reads.count) reads across \
            \(rowsWalked) row(s) and not one read plgs=tmdb — neither on a first visit (the row's \
            first-focus prewarm resolving before the card is reached) nor on a revisit (a metahub \
            miss repaired into a confirmed TMDB URL). Either the store/pending/prewarm path is not \
            working, or TMDB genuinely has no logo for any of these titles — check a few ids \
            against TMDB before concluding it is the fixture. Pass -debug.assumeTmdbOff on the \
            runner only when TMDB really is off. Reads:
            \(table)
            """)
            return
        }
        print("[test62] store path proven by \(proof)")

        // Warm path: leave the proof card and come straight back. The bitmap is cached and the
        // store entry is resolved, so the hero must still present a logo — and the ORIGIN may
        // legitimately move (a metahub guess giving way to the repaired TMDB URL is the whole point
        // of step 3 beating step 4 in `logoPlan`), so what is pinned is "still a logo, still from a
        // real source", not equality.
        //
        // Which way to leave is decided by looking, not by bookkeeping: at the row's leading edge a
        // Left press moves nothing, so if focus is still on the proof card after it, leave to the
        // RIGHT and come back instead.
        press(.left, times: 1, gap: 0.7)
        if readLogo(probe, pass: "leave", step: 0).fitem == proof.fitem {
            press(.right, times: 1, gap: 0.7)
            press(.left, times: 1, gap: 0.9)
        } else {
            press(.right, times: 1, gap: 0.9)
        }
        pause(1.0)
        let warm = readLogo(probe, pass: "warm", step: 0)
        XCTAssertEqual(warm.fitem, proof.fitem,
                       "the leave-and-return must land back on the same card: \(warm) vs \(proof)")
        XCTAssertEqual(warm.plg, "1", "a cache-warm revisit must still present the logo, never flick back to text: \(warm)")
        XCTAssertTrue(Self.logoSources.contains(warm.plgs),
                      "a cache-warm revisit must still name a real source (tmdb/metahub/addon): \(warm)")
        shot(app, "62b_warm_path_revisit")

        // Photo-contract invariants off the About pane's ring buffer.
        let lines = readHeroProbeAboutPane(app, shotPrefix: "62c")
        let presentLines = lines.filter { probeKind($0) == "present" }

        for line in presentLines {
            XCTAssertNotEqual(probeField(line, "same"), "1", "same=1 is the repaint signature the photo contract forbids: \(line)")
            XCTAssertNotNil(probeField(line, "logoSrc"), "every present line must carry the FEAT-42 logoSrc= field: \(line)")
        }

        // No item may present TWICE IN A ROW. The old bound (at most two `present` lines per item
        // in the buffer) only held for a one-visit walk and says nothing once this test walks a row
        // out and back; adjacency is the invariant that actually matters and is independent of how
        // far the walk goes — two commits for one item with no other item between them is the
        // double-paint BUG-42/BUG-90 exist to prevent. The one legitimate exception is
        // `backdrop=late`: `adoptLateBackdrop` deliberately re-commits the same item once when its
        // artwork lands after a deadline miss that painted nothing.
        for (index, line) in presentLines.enumerated() where index > 0 {
            guard let item = probeField(line, "item"),
                  let previous = probeField(presentLines[index - 1], "item"),
                  item == previous else { continue }
            XCTAssertEqual(probeField(line, "backdrop"), "late",
                           "\(item) presented twice with nothing between — only a late-backdrop adoption may do that: \(line)")
        }

        let restored = launchToHome(extraArguments: [])
        XCTAssertTrue(restored.state == .runningForeground)
    }
}
