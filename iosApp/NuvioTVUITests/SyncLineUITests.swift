import XCTest

/// Sync Line (P5 B19) legs. Skipped unless `PLAYER_BAR_PROBE=1`. `PLAYER_SMOKE_URL` is the smoke
/// video; `PLAYER_SMOKE_SUB_URL` an SRT beside it (cues every 2 s over the first 10 minutes, kept in
/// the gitignored `iosApp/build/smoke`). Pass both as `TEST_RUNNER_*`. The tvOS 27 sim never reports
/// `hasFocus`, so legs assert existence and values, and drive focus with fixed press counts.
final class SyncLineUITests: XCTestCase {
    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }

    private func launch(native: Bool, withSubtitle: Bool) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PLAYER_BAR_PROBE"] == "1", "PLAYER_BAR_PROBE not set")
        let url = try XCTUnwrap(env["PLAYER_SMOKE_URL"], "PLAYER_SMOKE_URL not set")
        let app = XCUIApplication()
        var args = ["-debug.mpvSmokeURL", url, "-player.nativeDolbyVision", native ? "YES" : "NO",
                    "-player.bufferMB", "8", "-debug.mpvSmokeStartOver", "YES"]
        if native { args += ["-debug.mpvSmokeEngine", "native"] }
        if withSubtitle {
            let sub = try XCTUnwrap(env["PLAYER_SMOKE_SUB_URL"], "PLAYER_SMOKE_SUB_URL not set")
            args += ["-debug.mpvSmokeSubtitleURL", sub]
        }
        app.launchArguments += args
        app.launch()
        let playerId = native ? "player.native" : "player.mpv"
        XCTAssertTrue(app.otherElements[playerId].waitForExistence(timeout: 40), "player did not appear")
        pause(8)   // playback running; the panel's recogniser attached
        return app
    }

    /// Down opens the panel; Right walks to the Subtitles tab.
    private func openSubtitlesTab(_ app: XCUIApplication) {
        remote.press(.down)
        XCTAssertTrue(app.otherElements["player.panel"].waitForExistence(timeout: 8), "panel did not present")
        pause(3)
        let tab = element(app, "player.panel.tab.subtitles")
        for _ in 0..<6 where (tab.value as? String) != "selected" {
            remote.press(.right)
            pause(0.6)
        }
        XCTAssertEqual(tab.value as? String, "selected", "Subtitles tab not selected")
    }

    /// Down from the tab row to the "Smoke EN" subtitle row; Select it; then Down to the Sync Line row.
    private func selectSmokeSubtitleAndReachSyncLine(_ app: XCUIApplication) {
        let smoke = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Smoke EN'")).firstMatch
        XCTAssertTrue(smoke.waitForExistence(timeout: 20), "no Smoke EN subtitle row")
        remote.press(.down)
        pause(0.8)
        // Walk Down until the Smoke EN row is picked (Off first, then the add-on row).
        for _ in 0..<4 where (smoke.value as? String) != "selected" {
            remote.press(.select)
            pause(1.5)
            if (smoke.value as? String) == "selected" { break }
            remote.press(.down)
            pause(0.8)
        }
        XCTAssertEqual(smoke.value as? String, "selected", "Smoke EN not selected")
        pause(2)
        let row = element(app, "player.panel.syncLine")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Sync Line row with an external subtitle selected")
        // Down through Timing caption -> delay chips -> Sync Line.
        for _ in 0..<3 where !row.hasFocus {
            remote.press(.down)
            pause(0.8)
        }
    }

    private func runSyncLine(native: Bool) throws {
        let app = try launch(native: native, withSubtitle: true)
        openSubtitlesTab(app)
        selectSmokeSubtitleAndReachSyncLine(app)
        remote.press(.select)
        let cue0 = element(app, "player.panel.syncLine.cue.0")
        XCTAssertTrue(cue0.waitForExistence(timeout: 12), "cue list never appeared")
        remote.press(.select)   // the anchor cue holds focus after 0.35 s
        pause(2)
        let value = element(app, "player.panel.subtitleDelay.value")
        XCTAssertTrue(value.waitForExistence(timeout: 5), "no delay value after picking a cue")
        XCTAssertNotEqual(value.label, "+0.00 s", "Sync Line left the delay at zero")
        if native {
            // Native snaps to the 100 ms step.
            let sec = Double(value.label.replacingOccurrences(of: " s", with: "")) ?? 0
            XCTAssertEqual((sec * 10).rounded(), sec * 10, accuracy: 0.001, "native delay not on the 0.1 s step: \(value.label)")
        }
        // Reset so the profile stays clean.
        let reset = element(app, "player.panel.subtitleDelay.reset")
        if reset.exists {
            for _ in 0..<8 where !reset.hasFocus { remote.press(.right); pause(0.4) }
            remote.press(.select)
        }
    }

    func testMpvSyncLineSetsDelay() throws {
        try runSyncLine(native: false)
    }

    func testNativeSyncLineSetsDelay() throws {
        try runSyncLine(native: true)
    }

    func testSyncLineHiddenWithoutExternalSubtitle() throws {
        let app = try launch(native: false, withSubtitle: false)
        openSubtitlesTab(app)
        XCTAssertTrue(element(app, "player.panel.subtitleDelay.value").waitForExistence(timeout: 5), "no Timing row")
        XCTAssertFalse(element(app, "player.panel.syncLine").exists, "Sync Line shown without an external subtitle")
    }
}
