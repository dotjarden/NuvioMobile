import XCTest

/// P5 Wave 1 (B20 audio effects, B23 per-show speed) panel legs. Gated on `PLAYER_BAR_PROBE=1`
/// and `PLAYER_SMOKE_URL` (pass as `TEST_RUNNER_*`), like the P1/P4 harness legs.
class PlayerAudioSpeedUITests: XCTestCase {
    let remote = XCUIRemote.shared

    // MARK: Harness

    private func launch(engine: String = "mpv", extra: [String] = []) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PLAYER_BAR_PROBE"] == "1", "PLAYER_BAR_PROBE not set")
        let url = try XCTUnwrap(env["PLAYER_SMOKE_URL"], "PLAYER_SMOKE_URL not set")
        let app = XCUIApplication()
        app.launchArguments += ["-debug.mpvSmokeURL", url, "-player.nativeDolbyVision", "NO",
                                "-player.bufferMB", "8", "-debug.mpvSmokeStartOver", "YES"]
        if engine == "native" { app.launchArguments += ["-player.nativeDolbyVision", "YES", "-debug.mpvSmokeEngine", "native"] }
        app.launchArguments += extra
        app.launch()
        let player = engine == "native" ? "player.native" : "player.mpv"
        XCTAssertTrue(app.otherElements[player].waitForExistence(timeout: 40), "player did not appear")
        Thread.sleep(forTimeInterval: 6)   // let playback start and the bar settle
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func openTab(_ app: XCUIApplication, _ name: String) {
        remote.press(.down)
        let tab = element(app, "player.panel.tab.\(name)")
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "no \(name) tab")
        for _ in 0..<6 where (tab.value as? String) != "selected" {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(tab.value as? String, "selected", "never reached the \(name) tab")
    }

    /// Down/Up/Left/Right toward `target` until it has focus.
    @discardableResult
    private func focusWalk(_ app: XCUIApplication, to target: XCUIElement, maxSteps: Int = 30) -> Bool {
        for _ in 0..<maxSteps {
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
            guard focused.exists else { remote.press(.down); Thread.sleep(forTimeInterval: 0.4); continue }
            let f = focused.frame, t = target.frame
            if f.midY < t.minY - 4 { remote.press(.down) }
            else if f.midY > t.maxY + 4 { remote.press(.up) }
            else if f.midX < t.midX { remote.press(.right) }
            else { remote.press(.left) }
            Thread.sleep(forTimeInterval: 0.45)
        }
        return target.hasFocus
    }

    private func press(_ app: XCUIApplication, _ id: String) {
        let target = element(app, id)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no \(id)")
        XCTAssertTrue(focusWalk(app, to: target), "focus never reached \(id)")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func waitValue(_ el: XCUIElement, _ expected: String, timeout: TimeInterval = 4) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if (el.value as? String) == expected || el.label == expected { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return (el.value as? String) == expected || el.label == expected
    }

    // MARK: Legs

    func testMpvAudioEffectsRows() throws {
        let app = try launch()
        openTab(app, "audio")
        let boost = element(app, "player.panel.audioFx.boost.value")
        XCTAssertTrue(boost.waitForExistence(timeout: 5), "no Boost value")
        XCTAssertTrue(waitValue(boost, "Off"), "Boost not Off: \(boost.label)")
        press(app, "player.panel.audioFx.boost.plus")
        XCTAssertTrue(waitValue(boost, "+2 dB"), "Boost not +2 dB: \(boost.label)")
        press(app, "player.panel.audioFx.boost.reset")
        XCTAssertTrue(waitValue(boost, "Off"), "Boost not reset: \(boost.label)")
        let dialogue = element(app, "player.panel.audioFx.mode.dialogue")
        press(app, "player.panel.audioFx.mode.dialogue")
        XCTAssertEqual(dialogue.value as? String, "selected", "Dialogue not selected")
        press(app, "player.panel.audioFx.mode.off")
        XCTAssertEqual(element(app, "player.panel.audioFx.mode.off").value as? String, "selected", "Off not restored")
    }

    func testNativeAudioTabHasNoEffects() throws {
        let app = try launch(engine: "native")
        openTab(app, "audio")
        XCTAssertFalse(element(app, "player.panel.audioFx.boost.value").waitForExistence(timeout: 2),
                       "native Audio tab shows Boost")
    }

    func testSpeedMemoryMpv() throws {
        let series = ["-debug.mpvSmokeSeries", "YES"]
        var app = try launch(extra: series)
        openTab(app, "playback")
        press(app, "player.panel.speed.1.25")
        XCTAssertEqual(element(app, "player.panel.speed.1.25").value as? String, "selected")
        press(app, "player.panel.speed.remember")
        XCTAssertEqual(element(app, "player.panel.speed.remember").value as? String, "on", "Remember not on")
        app.terminate()

        app = try launch(extra: series)
        openTab(app, "playback")
        let speed = element(app, "player.panel.speed.1.25")
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        XCTAssertTrue(waitValue(speed, "selected"), "1.25x not restored")
        // End state clean: forget the show's speed and put the rate back.
        press(app, "player.panel.speed.remember")
        XCTAssertEqual(element(app, "player.panel.speed.remember").value as? String, "off", "Remember not off")
        press(app, "player.panel.speed.1.0")
    }

    func testSpeedMemoryHiddenForMovies() throws {
        let app = try launch()
        openTab(app, "playback")
        XCTAssertTrue(element(app, "player.panel.speed.1.0").waitForExistence(timeout: 5), "no speed row")
        XCTAssertFalse(element(app, "player.panel.speed.remember").exists, "Remember row shown for a movie")
    }
}
