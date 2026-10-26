import XCTest

/// Stream picker A, P5 (`docs/stream-picker-addons-plan-2026-10-25.md` §2 "Wave P5"): one leg over
/// the whole picker, driven on the FA87 fixture (tvOS 26.5, which reports `hasFocus`).
///
///  - `testPickerChipsFocusAndPlay`: Detail -> Play opens the picker; the source panel is up with
///    one row per stream of both stub add-ons, an "All" chip selected plus one chip per add-on
///    ("ZZ Picker A, 3 sources" / "ZZ Picker B, 2 sources"), one section label per add-on, and the
///    FIRST ROW focused (the P4 device-pass fix `865ba971a`: the focus request re-issues until
///    focus is observed). Right on the list steps the chip selection with wrap (All -> A -> B ->
///    All) while focus stays on the list; Up from the first row lands on the selected chip; Right
///    on the chip row moves focus without selecting; Select on a chip selects it and keeps focus;
///    Down returns to the first row; Select on that row starts the player.
///
/// Knobs: two stream add-ons ("ZZ Picker A" with three direct links, "ZZ Picker B" with two) are
/// served by `DiscoveryStubServer` and installed through the DEBUG `-debug.addonManifestUrls` knob
/// on a seed launch (removed again by `-debug.addonManifestRemoveMatching /picker-zz-`, also on a
/// cleanup launch in a teardown block registered before the seed, so the fixture never keeps them;
/// teardown blocks, not `defer`s: `continueAfterFailure = false` unwinds past a `defer`). The add-on stub carries the
/// manifests and stream lists; a second stub only hosts the media URLs (it answers every path with
/// 404, so a chosen stream never plays, the leg only needs it chosen). `-debug.streamAutoPlayModeOverride
/// MANUAL` keeps auto-play from skipping the picker; `-debug.openDeepLink` goes straight to Dune's
/// Detail page; trailers are forced off so no cover buries Detail.
///
/// Skips when the Detail page never appears (network / fixture, not the picker), and, after the
/// panel, row-count, title and both-stub-chips checks have passed, when the fixture has other
/// movie stream add-ons installed (more than 5 rows: the stepping checks assume exactly the two
/// stubs). Every failure after the Play press names the identifiers and labels seen. XCUITest on
/// this runtime reports `hasFocus` on a chip only while it is selected, so focus on an unselected
/// chip is proven by the Select that follows (it can only select the chip that holds focus).
final class StreamPickerUITests: XCTestCase {
    let remote = XCUIRemote.shared

    private var printed: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers (duplicated per file, house rule)

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Prints a `[PickerLeg]` line and keeps it for the attachment at the end of the leg.
    private func say(_ text: String) {
        let line = "[PickerLeg] \(text)"
        print(line)
        printed.append(line)
    }

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists {
            // ui-legs: the shared verified step (Select only once "Chris" reads focused).
            DetailEntryRoute.selectChrisTile(self, app, timeout: 5)
        }
        return app
    }

    /// Identifier and label of every element holding focus, for failure messages.
    private func focusDump(_ app: XCUIApplication) -> String {
        let nodes = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        if nodes.isEmpty { return "<no focused element>" }
        return nodes.map { "[id=\($0.identifier) label=\($0.label)]" }.joined(separator: " ")
    }

    private func focusedLabel(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.label : "<none>"
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "stream_picker_row")
    }

    private func chip(_ app: XCUIApplication, _ suffix: String) -> XCUIElement {
        element(app, "stream_picker_chip_\(suffix)")
    }

    /// Waits until the picker lists exactly `count` rows (`>= count` when `atLeast`).
    private func waitRows(_ app: XCUIApplication, _ count: Int, atLeast: Bool = false, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let now = rows(app).count
            if atLeast ? now >= count : now == count { return true }
            pause(0.25)
        }
        let now = rows(app).count
        return atLeast ? now >= count : now == count
    }

    /// Polls `condition` every 0.25 s until it holds or `timeout` passes (review r1 P2: a single
    /// read after a press races the StateFlow → collector → SwiftUI → AX snapshot chain).
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(0.25)
        }
        return condition()
    }

    private func waitFocus(_ target: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if target.exists && target.hasFocus { return true }
            pause(0.25)
        }
        return target.exists && target.hasFocus
    }

    /// "ZZ Picker A, 3 sources" -> ("ZZ Picker A", 3). Count is nil for "loading" / "failed".
    private func parseChip(_ label: String) -> (name: String, count: Int?) {
        guard let comma = label.range(of: ", ", options: .backwards) else { return (label, nil) }
        let name = String(label[..<comma.lowerBound])
        let tail = String(label[comma.upperBound...])
        return (name, Int(tail.split(separator: " ").first ?? ""))
    }

    private func chipLabels(_ app: XCUIApplication) -> [String] {
        (0..<8).compactMap { index in
            let node = chip(app, "\(index)")
            return node.exists ? node.label : nil
        }
    }

    // MARK: - Fixture add-ons

    private static let stubPrefix = "/picker-zz-"

    private func manifest(id: String, name: String) -> String {
        """
        {"id":"\(id)","version":"1.0.0","name":"\(name)","description":"Stream picker P5 leg","resources":[{"name":"stream","types":["movie"],"idPrefixes":["tt"]}],"types":["movie"],"catalogs":[]}
        """
    }

    private func streams(_ items: [(name: String, title: String, file: String)], prefix: String, media: String) -> String {
        let body = items.map { item in
            "{\"name\":\"\(item.name)\",\"title\":\"\(item.title)\",\"url\":\"\(media)\(prefix)media/\(item.file)\"}"
        }.joined(separator: ",")
        return "{\"streams\":[\(body)]}"
    }

    // MARK: - The leg

    func testPickerChipsFocusAndPlay() throws {
        // Media host: answers 404 JSON for every path (the stub has no routes), so the stream URLs
        // are real, parseable loopback links that never need to play. The add-on stub learns its
        // own origin only after start(), but the bodies need the MEDIA origin, so the media stub
        // starts first.
        // Review r1 P1: `continueAfterFailure = false` stops a failing test by unwinding past Swift
        // `defer`s, so every cleanup is a teardown block (LIFO: the attachment is registered first
        // and runs last, the cleanup launch is registered last and runs first).
        addTeardownBlock { [self] in
            let transcript = printed.joined(separator: "\n")
            let attachment = XCTAttachment(string: transcript)
            attachment.name = "picker-leg-log"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let mediaStub = DiscoveryStubServer()
        try mediaStub.start()
        addTeardownBlock { mediaStub.stop() }
        let media = mediaStub.origin

        let addonStub = DiscoveryStubServer(routes: [
            (prefix: "/picker-zz-a/manifest.json", body: manifest(id: "zz.picker.a", name: "ZZ Picker A")),
            (prefix: "/picker-zz-a/stream/movie/", body: streams([
                ("ZZ A\\n1080p", "Dune 2021 1080p WEB-DL", "a1.mp4"),
                ("ZZ A\\n720p", "Dune 2021 720p WEB", "a2.mp4"),
                ("ZZ A\\n480p", "Dune 2021 480p", "a3.mp4"),
            ], prefix: "/picker-zz-a/", media: media)),
            (prefix: "/picker-zz-b/manifest.json", body: manifest(id: "zz.picker.b", name: "ZZ Picker B")),
            (prefix: "/picker-zz-b/stream/movie/", body: streams([
                ("ZZ B\\n2160p", "Dune 2021 2160p", "b1.mp4"),
                ("ZZ B\\n1080p", "Dune 2021 1080p", "b2.mp4"),
            ], prefix: "/picker-zz-b/", media: media)),
        ])
        try addonStub.start()
        addTeardownBlock { addonStub.stop() }

        let common = [
            "-home_layout", "classic", "-debug.rememberLastProfile", "NO",
            "-detail_trailer_autoplay", "NO", "-debug.trailerForceNoTrailer", "YES",
            "-hero_trailer_autoplay", "NO", "-debug.streamAutoPlayModeOverride", "MANUAL",
        ]

        // Cleanup launch (registered BEFORE the seed launch, review r2: `launch` itself can fail
        // after the seed applied): the remove knob alone, so the fixture never keeps the stub add-ons.
        addTeardownBlock { [self] in
            XCUIApplication().terminate()
            let cleanup = launch(common + ["-debug.addonManifestRemoveMatching", Self.stubPrefix])
            pause(10)
            cleanup.terminate()
        }

        // 1. Seed launch: install both add-ons (applied on Home's first add-ons emission).
        let seed = launch(common + [
            "-debug.addonManifestRemoveMatching", Self.stubPrefix,
            "-debug.addonManifestUrls",
            "\(addonStub.origin)/picker-zz-a/manifest.json,\(addonStub.origin)/picker-zz-b/manifest.json",
        ])
        pause(14)
        seed.terminate()

        // 2. Leg launch: Dune's Detail page, then Play.
        let app = launch(common + [
            "-debug.openDeepLink", "nuviotv://title?id=tt1160419&type=movie&name=Dune",
            "-detail_layout", "cinematic", "-home_upcoming_row_enabled", "NO",
        ])

        var detailUp = false
        for _ in 0..<90 {
            if element(app, "detail_hero").exists || element(app, "detail_action_play").exists {
                detailUp = true
                break
            }
            pause(0.5)
        }
        if !detailUp {
            throw XCTSkip("the deep link never produced a Detail page — network or fixture, not the picker")
        }

        var playFocused = false
        for _ in 0..<60 {
            let label = focusedLabel(app)
            if label.hasPrefix("Play") || label.hasPrefix("Resume") {
                playFocused = true
                break
            }
            pause(0.25)
        }
        guard playFocused else {
            XCTFail("focus never reached Play/Resume on Detail; focused: \(focusDump(app))")
            return
        }
        remote.press(.select)

        // a. The panel.
        XCTAssertTrue(element(app, "stream_picker_source_panel").waitForExistence(timeout: 20),
                      "stream_picker_source_panel never appeared; focused: \(focusDump(app))")
        say("panel up")

        // b. Rows: 3 (A) + 2 (B) under "All". The list is a LazyVStack, so XCUITest only sees the
        // rows realized so far (run 1 saw 4 of 5 on open); the count is read after a Down walk to
        // the end of the list, then focus is walked back to the first row.
        XCTAssertTrue(waitRows(app, 4, atLeast: true, timeout: 20),
                      "expected >= 4 stream_picker_row on open, saw \(rows(app).count); chips: \(chipLabels(app)); focused: \(focusDump(app)) (seed refused or stub unreachable?)")
        say("rows realized on open = \(rows(app).count)")
        let expectedTotal = chipLabels(app).compactMap { parseChip($0).count }.reduce(0, +)
        XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                      "the first stream_picker_row never took focus; focused: \(focusDump(app))")
        say("first row focused on open")
        // Review r2: once the list has scrolled, `boundBy: 0` is the first REALIZED row, so the
        // first row is known by its label from here on.
        let firstRowLabel = rows(app).element(boundBy: 0).label
        let firstRowByLabel = rows(app).matching(NSPredicate(format: "label == %@", firstRowLabel)).firstMatch
        // Review r1 P2 / r2: press Down `expectedTotal + 2` times (capped; the lazy list grows only
        // as focus nears its end, so a "stops growing" rule quit too early on run 9) reading the
        // realized count after each press; the Up walk back is bounded by the first row's label,
        // so a dropped press cannot derail the leg.
        var total = rows(app).count
        for _ in 0..<min(expectedTotal + 2, 14) {
            remote.press(.down)
            pause(0.5)
            total = max(total, rows(app).count)
        }
        var ups = 0
        while ups < 12, !(firstRowByLabel.exists && firstRowByLabel.hasFocus) {
            remote.press(.up)
            pause(0.5)
            ups += 1
        }
        XCTAssertTrue(waitFocus(firstRowByLabel, timeout: 5),
                      "focus did not return to the first row after the walk (\(ups) Ups); focused: \(focusDump(app))")
        XCTAssertTrue(rows(app).element(boundBy: 0).hasFocus,
                      "the first realized row is not the first row after the walk; focused: \(focusDump(app))")
        XCTAssertGreaterThanOrEqual(total, 5,
                                    "expected >= 5 stream_picker_row after walking the list, saw \(total); chips: \(chipLabels(app)) (seed refused or stub unreachable?)")
        let exact = total == 5 && expectedTotal == 5
        say("rows under All = \(total), chip counts sum = \(expectedTotal) (exact fixture: \(exact))")

        // c. Info panel title.
        // Scoped to the info panel (review r1 P3): Detail's own logo under the cover carries the
        // same label.
        let infoPanel = element(app, "stream_picker_info_panel")
        XCTAssertTrue(infoPanel.waitForExistence(timeout: 10), "stream_picker_info_panel never appeared")
        let titleImage = infoPanel.images["Dune"]
        let titleAny = infoPanel.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Dune")).firstMatch
        XCTAssertTrue(titleAny.waitForExistence(timeout: 10),
                      "no element labelled \"Dune\" in the info panel; focused: \(focusDump(app))")
        say("title shown as \(titleImage.exists ? "image" : "text")")
        let progress = infoPanel.descendants(matching: .any)["stream_picker_progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "stream_picker_progress not under the info panel")
        say("progress line: \(progress.label)")

        // d. Chips.
        let all = chip(app, "all")
        XCTAssertTrue(all.exists, "stream_picker_chip_all missing")
        XCTAssertTrue(all.isSelected, "stream_picker_chip_all not selected on open; label: \(all.label)")
        XCTAssertTrue(chip(app, "0").exists && chip(app, "1").exists,
                      "stream_picker_chip_0 / _1 missing; chips: \(chipLabels(app))")
        let labels = chipLabels(app)
        say("chips = \(labels)")
        XCTAssertTrue(labels.contains("ZZ Picker A, 3 sources") && labels.contains("ZZ Picker B, 2 sources"),
                      "both stub chips must be present whatever else is installed; chips: \(labels)")
        if !exact {
            // Review r1 P2: the stepping checks assume exactly the two stub add-ons; a fixture with
            // more stream add-ons skips (the teardown blocks still run), it never passes silently.
            throw XCTSkip("fixture has extra movie stream add-ons (\(labels), \(total) rows): the stepping checks assume the two stubs alone")
        } else {
            XCTAssertEqual(Set(labels.prefix(2)), Set(["ZZ Picker A, 3 sources", "ZZ Picker B, 2 sources"]),
                           "chip labels: \(labels)")
            XCTAssertFalse(chip(app, "2").exists, "unexpected stream_picker_chip_2: \(chip(app, "2").label)")

            // e. Section labels under "All".
            let sections = app.descendants(matching: .any).matching(identifier: "stream_picker_section_label").count
            XCTAssertEqual(sections, 2, "stream_picker_section_label count under All")
        }

        // f. Initial focus on the first row (P4 device-pass fix 865ba971a) was read in b, before
        // the walk; here only that focus is back on the first row.
        XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                      "the first stream_picker_row does not hold focus; focused: \(focusDump(app))")

        if exact {
            let first = parseChip(chip(app, "0").label)
            let second = parseChip(chip(app, "1").label)
            let firstCount = first.count ?? -1
            let secondCount = second.count ?? -1
            say("chip order = \(first.name), \(second.name)")

            // g. Right from the list steps the selection (All -> chip_0 -> chip_1 -> All).
            remote.press(.right)
            XCTAssertTrue(waitUntil(timeout: 5) { chip(app, "0").isSelected }, "Right did not select chip_0; chips: \(chipLabels(app)); focused: \(focusDump(app))")
            XCTAssertFalse(all.isSelected, "\"All\" still selected after Right")
            XCTAssertTrue(waitRows(app, firstCount, timeout: 10),
                          "rows after first step: \(rows(app).count), expected \(firstCount) for \(first.name)")
            XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                          "the step moved focus off the list; focused: \(focusDump(app))")

            remote.press(.right)
            XCTAssertTrue(waitUntil(timeout: 5) { chip(app, "1").isSelected }, "second Right did not select chip_1; chips: \(chipLabels(app))")
            XCTAssertFalse(chip(app, "0").isSelected, "chip_0 still selected after the second Right")
            XCTAssertTrue(waitRows(app, secondCount, timeout: 10),
                          "rows after second step: \(rows(app).count), expected \(secondCount) for \(second.name)")

            remote.press(.right)
            XCTAssertTrue(waitUntil(timeout: 5) { all.isSelected }, "third Right did not wrap to \"All\"; chips: \(chipLabels(app))")
            // Back under "All" the lazy list realizes 4 of the 5 rows on screen (as on open).
            XCTAssertTrue(waitRows(app, 4, atLeast: true, timeout: 10), "rows after the wrap: \(rows(app).count), expected >= 4")
            say("right-step cycle ok")

            // h. Up from the first row lands on the selected chip ("All").
            XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                          "focus left the list before the Up check; focused: \(focusDump(app))")
            remote.press(.up)
            pause(0.6)
            XCTAssertTrue(waitFocus(all, timeout: 5), "Up from the first row did not land on stream_picker_chip_all; focused: \(focusDump(app))")
            // Right on the chip row moves focus; it is NOT a selection change. XCUITest on the FA87
            // runtime reports `hasFocus` on the "All" chip but NOT on the ForEach chips (runs 4 and
            // 5 of this leg: no focused element for 5 s while the captured frames show chip_0's
            // lifted platter), so focus on a ForEach chip is read softly and the Select that
            // follows is the oracle: it can only select chip_0 if chip_0 holds focus.
            remote.press(.right)
            pause(0.6)
            say("chip_0 reports focus after Right: \(waitFocus(chip(app, "0"), timeout: 2)) (soft read); focused: \(focusDump(app))")
            XCTAssertTrue(all.isSelected, "\"All\" lost its selection on a focus move")
            XCTAssertFalse(chip(app, "0").isSelected, "a focus move along the chip row selected chip_0")
            // Select on the focused chip selects it and keeps focus there (Down then re-enters the list).
            remote.press(.select)
            XCTAssertTrue(waitUntil(timeout: 5) { chip(app, "0").isSelected }, "Select on chip_0 did not select it (focus was not on chip_0 after Right); chips: \(chipLabels(app))")
            XCTAssertFalse(all.isSelected, "\"All\" still selected after Select on chip_0")
            // A selected chip does report focus (run 6): hard assert (review r1 P2).
            XCTAssertTrue(waitFocus(chip(app, "0"), timeout: 5), "focus left chip_0 after Select; focused: \(focusDump(app))")
            XCTAssertTrue(waitRows(app, firstCount, timeout: 10),
                          "rows after selecting chip_0: \(rows(app).count), expected \(firstCount)")
            remote.press(.down)
            XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                          "Down from the chip did not focus the first row; focused: \(focusDump(app))")
            say("chip focus and select ok")

            // Review r1 P2: "Up lands on the SELECTED chip" with a chip that is not next to the
            // refresh button, so a geometric landing cannot pass it: step to chip_1 from the list,
            // Down/Up, and hard-assert chip_1 (selected chips report focus).
            remote.press(.right)
            XCTAssertTrue(waitUntil(timeout: 5) { chip(app, "1").isSelected }, "Right from the list did not step to chip_1; chips: \(chipLabels(app))")
            XCTAssertTrue(waitRows(app, secondCount, timeout: 10),
                          "rows after stepping to chip_1: \(rows(app).count), expected \(secondCount)")
            XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                          "the step to chip_1 moved focus off the list; focused: \(focusDump(app))")
            remote.press(.up)
            XCTAssertTrue(waitFocus(chip(app, "1"), timeout: 5),
                          "Up from the first row did not land on the selected chip_1; focused: \(focusDump(app))")
            // Reviewer's decisive check on the missing hasFocus: Left onto the UNSELECTED chip_0.
            remote.press(.left)
            pause(0.6)
            say("unselected chip_0 reports focus after Left from selected chip_1: \(waitFocus(chip(app, "0"), timeout: 2)) (soft read; false = the gap follows selection, not ForEach)")
            remote.press(.right)
            XCTAssertTrue(waitFocus(chip(app, "1"), timeout: 5), "Right back onto the selected chip_1 lost focus; focused: \(focusDump(app))")
            remote.press(.down)
            XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5),
                          "Down from chip_1 did not focus the first row; focused: \(focusDump(app))")
            say("up onto the selected chip_1 ok")
        }

        // i. No progress for this title on the fixture: no resume pill.
        let pill = element(app, "stream_picker_resume_pill")
        if pill.exists {
            say("resume pill present, label: \(pill.label)")
        } else {
            say("resume pill absent")
        }

        // j. Select on the first row plays.
        let firstRow = rows(app).element(boundBy: 0)
        XCTAssertTrue(waitFocus(firstRow, timeout: 5),
                      "the first row does not hold focus before the play press; focused: \(focusDump(app))")
        remote.press(.select)
        let playerIds = ["player.native", "player.mpv", "player.loadingOverlay"]
        var reached: String?
        for _ in 0..<120 {
            if let id = playerIds.first(where: { element(app, $0).exists }) {
                reached = id
                break
            }
            pause(0.25)
        }
        XCTAssertNotNil(reached, "no player element (\(playerIds)) within 30 s of the row press; focused: \(focusDump(app))")
        say("player reached via \(reached ?? "<none>")")

        // Best effort back out; the cleanup launch resets the fixture anyway.
        for _ in 0..<3 {
            remote.press(.menu)
            pause(1)
            if element(app, "stream_picker_source_panel").exists || element(app, "detail_hero").exists { break }
        }
    }

    // MARK: - Chip row overflow

    /// P5 device pass: with seven stub add-ons the chip row overflows the panel. Left from the first
    /// row wraps the selection to the LAST chip; the row must scroll that chip inside the panel
    /// (the P4 device-pass fix, `865ba971a`, which the box showed as a no-op: the chip stayed cut
    /// at the panel edge). Prints the chip row's and the panel's frames so a layout cause (a chip
    /// row laid out wider than the panel) can be told from a scroll that never ran.
    func testChipRowScrollsTheSelectedChipIntoView() throws {
        let mediaStub = DiscoveryStubServer()
        try mediaStub.start()
        addTeardownBlock { mediaStub.stop() }
        let media = mediaStub.origin
        let names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf"]
        var routes: [(prefix: String, body: String)] = []
        for (index, name) in names.enumerated() {
            let prefix = "/picker-zz-\(index)/"
            routes.append((prefix: "\(prefix)manifest.json", body: manifest(id: "zz.picker.\(index)", name: "ZZ \(name)")))
            routes.append((prefix: "\(prefix)stream/movie/", body: streams([
                ("ZZ \(name)\\n1080p", "Dune 2021 1080p \(name)", "\(index).mp4"),
            ], prefix: prefix, media: media)))
        }
        let addonStub = DiscoveryStubServer(routes: routes)
        try addonStub.start()
        addTeardownBlock { addonStub.stop() }

        let common = [
            "-home_layout", "classic", "-debug.rememberLastProfile", "NO",
            "-detail_trailer_autoplay", "NO", "-debug.trailerForceNoTrailer", "YES",
            "-hero_trailer_autoplay", "NO", "-debug.streamAutoPlayModeOverride", "MANUAL",
        ]
        addTeardownBlock { [self] in
            XCUIApplication().terminate()
            let cleanup = launch(common + ["-debug.addonManifestRemoveMatching", Self.stubPrefix])
            pause(10)
            cleanup.terminate()
        }
        let urls = names.indices.map { "\(addonStub.origin)/picker-zz-\($0)/manifest.json" }.joined(separator: ",")
        let seed = launch(common + ["-debug.addonManifestRemoveMatching", Self.stubPrefix, "-debug.addonManifestUrls", urls])
        pause(16)
        seed.terminate()

        let app = launch(common + [
            "-debug.openDeepLink", "nuviotv://title?id=tt1160419&type=movie&name=Dune",
            "-detail_layout", "cinematic", "-home_upcoming_row_enabled", "NO",
        ])
        var detailUp = false
        for _ in 0..<90 {
            if element(app, "detail_hero").exists || element(app, "detail_action_play").exists { detailUp = true; break }
            pause(0.5)
        }
        if !detailUp { throw XCTSkip("the deep link never produced a Detail page — network or fixture, not the picker") }
        var playFocused = false
        for _ in 0..<60 {
            let label = focusedLabel(app)
            if label.hasPrefix("Play") || label.hasPrefix("Resume") { playFocused = true; break }
            pause(0.25)
        }
        guard playFocused else { XCTFail("focus never reached Play/Resume on Detail; focused: \(focusDump(app))"); return }
        remote.press(.select)

        // `.firstMatch`: the container identifiers resolve to more than one node (run 1 of this leg).
        let panel = app.descendants(matching: .any).matching(identifier: "stream_picker_source_panel").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "stream_picker_source_panel never appeared")
        XCTAssertTrue(waitUntil(timeout: 20) { chipLabels(app).count >= names.count },
                      "expected \(names.count) chips, saw \(chipLabels(app))")
        XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 10),
                      "the first row never took focus; focused: \(focusDump(app))")
        let lastIndex = chipLabels(app).count - 1
        let last = chip(app, "\(lastIndex)")
        // The chip row's own identifier (a ScrollView with a focus section) is not exposed on this
        // runtime (run 2: no match), so the row is read through its chips: the refresh chip's
        // leading edge and the last chip's trailing edge.
        let refresh = element(app, "stream_picker_chip_refresh")
        func rowFrame() -> String { "refresh.minX=\(refresh.frame.minX) last.maxX=\(last.frame.maxX)" }
        say("overflow: panel=\(panel.frame) \(rowFrame()) all=\(chip(app, "all").frame) last(\(lastIndex))=\(last.frame) before the step")

        remote.press(.left)
        XCTAssertTrue(waitUntil(timeout: 5) { last.isSelected }, "Left from the first row did not wrap to the last chip; chips: \(chipLabels(app))")
        pause(1.5)
        say("overflow: \(rowFrame()) all=\(chip(app, "all").frame) last(\(lastIndex))=\(last.frame) after the step")
        XCTAssertLessThanOrEqual(last.frame.maxX, panel.frame.maxX - 8,
                                 "the selected last chip is not inside the panel: last=\(last.frame) panel=\(panel.frame) \(rowFrame())")
        XCTAssertTrue(waitFocus(rows(app).element(boundBy: 0), timeout: 5), "the step moved focus off the list; focused: \(focusDump(app))")
    }
}
