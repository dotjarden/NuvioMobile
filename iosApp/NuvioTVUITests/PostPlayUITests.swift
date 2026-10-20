import XCTest

/// P5 B22 post-play More Like This legs (spec C). Written, not run by the build agent.
///
/// Each leg resumes a short fixture a few seconds before its end (`-debug.mpvSmokeResumeSec`),
/// so the end arrives quickly with no Up Next (a movie context). `-debug.postPlayStubTitles 3`
/// stands in for the repository call and `-debug.mpvSmokePostPlay YES` records a poster pick in
/// the 1 pt `debug_postPlayOpened` label instead of pushing a page.
///
/// Gates: mpv legs need `PLAYER_BAR_PROBE=1`, native legs `PLAYER_NATIVE_PROBE=1`; both need
/// `PLAYER_SMOKE_URL` (a short fixture) and `PLAYER_SMOKE_DURATION_SEC` (its length in seconds),
/// passed as `TEST_RUNNER_*`.
class PostPlayUITests: XCTestCase {
    let remote = XCUIRemote.shared

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func parse(_ text: String) -> [String: String] {
        NativePlayerParityUITests.parse(text)
    }

    /// Launches the smoke rig a few seconds before the fixture's end. `native` picks the engine.
    private func launch(native: Bool) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env[native ? "PLAYER_NATIVE_PROBE" : "PLAYER_BAR_PROBE"] == "1",
                          native ? "PLAYER_NATIVE_PROBE not set" : "PLAYER_BAR_PROBE not set")
        let url = try XCTUnwrap(env["PLAYER_SMOKE_URL"], "PLAYER_SMOKE_URL not set")
        let duration = try XCTUnwrap(env["PLAYER_SMOKE_DURATION_SEC"].flatMap(Double.init),
                                     "PLAYER_SMOKE_DURATION_SEC not set")
        let resume = max(duration - 8, 12)   // the resume seek only applies above 10 s
        let app = XCUIApplication()
        var args = ["-debug.mpvSmokeURL", url, "-debug.mpvSmokeStartOver", "YES",
                    "-debug.mpvSmokeResumeSec", String(resume),
                    "-debug.postPlayStubTitles", "3", "-debug.mpvSmokePostPlay", "YES"]
        if native {
            args += ["-player.nativeDolbyVision", "YES", "-debug.mpvSmokeEngine", "native"]
        } else {
            args += ["-player.nativeDolbyVision", "NO", "-player.bufferMB", "8"]
        }
        app.launchArguments += args
        app.launch()
        let player = app.otherElements[native ? "player.native" : "player.mpv"]
        XCTAssertTrue(player.waitForExistence(timeout: 40), "player did not appear")
        return app
    }

    private func waitForPostPlay(_ app: XCUIApplication) {
        XCTAssertTrue(element(app, "postplay.replay").waitForExistence(timeout: 60),
                      "the post-play screen never appeared")
    }

    private func selectFirstPoster(_ app: XCUIApplication) {
        let poster = element(app, "postplay.moreLikeThis.0")
        XCTAssertTrue(poster.waitForExistence(timeout: 10), "no More Like This row")
        // Focus starts on Play Again; Down enters the row (a focus section under the two buttons,
        // with Back to Details between: two Downs).
        for _ in 0..<3 where !poster.hasFocus {
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        remote.press(.select)
        let opened = element(app, "debug_postPlayOpened")
        XCTAssertTrue(opened.waitForExistence(timeout: 10), "no opened label")
        let end = Date().addingTimeInterval(10)
        while Date() < end, opened.label != "stub-1" { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(opened.label, "stub-1", "the poster pick never reached the presenter")
        XCTAssertTrue(element(app, "postplay.replay").waitForNonExistence(timeout: 10),
                      "the player did not close after the pick")
    }

    func testMpvPostPlayRowOpensTitle() throws {
        let app = try launch(native: false)
        waitForPostPlay(app)
        selectFirstPoster(app)
    }

    func testNativePostPlayRowOpensTitle() throws {
        let app = try launch(native: true)
        waitForPostPlay(app)
        selectFirstPoster(app)
    }

    /// Select on Play Again (default focus) restarts the item; mpv's seek probe reads the position.
    func testPostPlayPlayAgainUnchanged() throws {
        let app = try launch(native: false)
        waitForPostPlay(app)
        remote.press(.select)
        let seek = element(app, "debug_seekProbe")
        XCTAssertTrue(seek.waitForExistence(timeout: 10), "no seek probe")
        let end = Date().addingTimeInterval(20)
        var pos = Double.greatestFiniteMagnitude
        while Date() < end {
            pos = Double(parse(seek.label)["pos"] ?? "") ?? Double.greatestFiniteMagnitude
            if pos < 5 { break }
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertLessThan(pos, 5, "Play Again did not restart: \(seek.label)")
    }
}
