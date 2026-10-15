import XCTest

/// Batch A (Steven's beta.19-rc3 verdict 2026-10-06, follow-ups 2026-10-08), agent δ's legs:
///
///  - FEAT-62, Rail = Hidden ("hide it on the first line, show it on Left/Back"): the rail is off
///    screen at rest on Home's row 0, Left from the first card reveals it, Right hides it again,
///    Menu reveals it.
///  - FEAT-65, Open Last Profile at Launch: with the flag on (here the DEBUG in-memory override
///    `-debug.rememberLastProfile YES`, never persisted) a cold launch lands in the shell without
///    the picker; with it off (`NO`) the picker shows.
///
/// Oracle: the rail's always-mounted DEBUG probe `rail_state … vis= shown= expanded= reason= …`
/// (see `NavigationRailUITests`). Fixture: FA87 (tvOS 26.5), guest "Chris" with Cinemeta, a
/// profile chosen on earlier runs (`hasEverSelectedProfile`), no PIN. Rail mode lands launch
/// focus on Stage row 0's first card. Helpers are this file's own (the harness's duplication rule).
final class BatchARailProfileUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Basics

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func poll(_ timeout: TimeInterval, step: TimeInterval = 0.15, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(step)
        }
        return condition()
    }

    private static func railArguments(visibility: String) -> [String] {
        ["-sidebar_style", "rail", "-rail_visibility", visibility, "-home_layout", "stage",
         "-home_upcoming_row_enabled", "NO", "-inline_trailers_enabled", "NO", "-discover_placement", "off",
         // FEAT-65: never let a fixture with the flag on skip the picker these legs drive.
         "-debug.rememberLastProfile", "NO"]
    }

    private func pickerButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
    }

    /// Fresh launch through the profile picker (Left, Left, Select: "Chris" is the first profile).
    @discardableResult
    private func launchThroughPicker(_ arguments: [String], settle: TimeInterval = 16) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(pickerButton(app).waitForExistence(timeout: 90), "profile picker never appeared — is the FA87 fixture set up?")
        if pickerButton(app).exists {
            remote.press(.left)
            pause(0.5)
            remote.press(.left)
            pause(0.5)
            remote.press(.select)
        }
        pause(settle)
        return app
    }

    // MARK: - Readouts

    private func railState(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)["rail_state"].firstMatch
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

    private func rail(_ app: XCUIApplication, _ key: String) -> String? {
        Self.token(railState(app), key)
    }

    // MARK: - FEAT-62

    func testFEAT62_RailHiddenRevealsOnLeftAndMenu() throws {
        let app = launchThroughPicker(Self.railArguments(visibility: "hidden"))
        guard poll(10, step: 0.5, { !railState(app).isEmpty }) else {
            XCTFail("rail_state never appeared with -sidebar_style rail (DEBUG build?)")
            return
        }
        let start = railState(app)
        XCTAssertEqual(Self.token(start, "vis"), "hidden", "\(start)")
        XCTAssertEqual(Self.token(start, "shown"), "0", "Hidden: nothing at rest on Home's row 0: \(start)")
        XCTAssertEqual(Self.token(start, "expanded"), "0", "\(start)")
        XCTAssertEqual(Self.token(start, "inset"), "0", "Hidden reserves no width: \(start)")
        shot("feat62_0_rest")

        // Left from row 0's first card (the launch focus; a short Left walk in case it is not card 0)
        // reveals it. The rail stays hidden while the walk moves along the row.
        var opened = false
        for _ in 0..<6 where !opened {
            remote.press(.left)
            opened = poll(1.2) { rail(app, "expanded") == "1" }
            if !opened { XCTAssertEqual(rail(app, "shown"), "0", "a Left along the row must not show the rail: \(railState(app))") }
        }
        XCTAssertTrue(opened, "Left from the first card must reveal the rail: \(railState(app))")
        XCTAssertEqual(rail(app, "shown"), "1", "\(railState(app))")
        XCTAssertEqual(rail(app, "reason"), "left", "\(railState(app))")
        shot("feat62_1_left")

        // Right hides it again.
        remote.press(.right)
        XCTAssertTrue(poll(2.5) { rail(app, "expanded") == "0" && rail(app, "shown") == "0" },
                      "Right must leave the rail and hide it: \(railState(app))")
        shot("feat62_2_right")

        // Menu reveals it (rail closed and unfocused: Menu at the tab root opens it).
        remote.press(.menu)
        XCTAssertTrue(poll(2.5) { rail(app, "expanded") == "1" }, "Menu must reveal the rail: \(railState(app))")
        XCTAssertEqual(rail(app, "shown"), "1", "\(railState(app))")
        XCTAssertEqual(rail(app, "reason"), "menu", "\(railState(app))")
        shot("feat62_3_menu")

        // Right hides it again. Menu is NOT pressed again: inside a Menu-opened rail it leaves the app.
        remote.press(.right)
        XCTAssertTrue(poll(3.0) { rail(app, "expanded") == "0" && rail(app, "shown") == "0" },
                      "Right must hide a Menu-opened rail too: \(railState(app))")
    }

    // MARK: - FEAT-65

    func testFEAT65_RememberLastProfileSkipsThePicker() {
        var arguments = Self.railArguments(visibility: "always")
        arguments.removeLast(2)
        arguments += ["-debug.rememberLastProfile", "YES"]
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        // The shell's rail probe exists only past the profile gate.
        let landed = poll(90, step: 0.5) { !railState(app).isEmpty || pickerButton(app).exists }
        XCTAssertTrue(landed, "neither the shell nor the picker appeared")
        XCTAssertFalse(pickerButton(app).exists,
                       "with the flag on and a non-PIN last profile the picker must not show (fixture needs a profile chosen before)")
        XCTAssertTrue(poll(10, step: 0.5) { !railState(app).isEmpty }, "the app must land in the shell (rail_state)")
        shot("feat65_auto_enter")
    }

    func testFEAT65_FlagOffShowsThePicker() {
        let app = XCUIApplication()
        app.launchArguments = Self.railArguments(visibility: "always")   // carries `-debug.rememberLastProfile NO`
        app.launch()
        XCTAssertTrue(pickerButton(app).waitForExistence(timeout: 90), "with the flag off the picker must show")
        XCTAssertTrue(railState(app).isEmpty, "the shell must not be up behind the picker")
        shot("feat65_picker")
    }
}
