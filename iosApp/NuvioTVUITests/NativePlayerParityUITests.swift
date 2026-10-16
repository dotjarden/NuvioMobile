import XCTest
import UIKit

/// P4 native-engine parity legs (spec `docs/research/player-p4-spec-native-parity.md` §10.2).
///
/// Native legs launch the real `PlayerScreen` through the mpv smoke rig with
/// `-debug.mpvSmokeEngine native`, which sets `PlaybackContext.forcedEngine = .native`: the probe
/// and the silent fallback are skipped, so a leg can never quietly pass on mpv. They read the DEBUG
/// `debug_nativeProbe` label (`pos= speed= paused= bar= card= stage= chapters= subs= late=`).
/// Gated on `PLAYER_NATIVE_PROBE=1` and `PLAYER_SMOKE_URL` (pass them as `TEST_RUNNER_*`).
///
/// The mpv regression leg uses the P1 transport harness (`PLAYER_BAR_PROBE=1`).
class NativePlayerParityUITests: XCTestCase {
    let remote = XCUIRemote.shared

    // MARK: Native harness

    /// Launches the smoke rig on the native engine and waits until playback has started.
    func launchNative(url fixture: String? = nil, extra: [String] = []) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PLAYER_NATIVE_PROBE"] == "1", "PLAYER_NATIVE_PROBE not set")
        let url = try fixture ?? XCTUnwrap(env["PLAYER_SMOKE_URL"], "PLAYER_SMOKE_URL not set")
        let app = XCUIApplication()
        app.launchArguments += ["-debug.mpvSmokeURL", url, "-player.nativeDolbyVision", "YES",
                                "-debug.mpvSmokeEngine", "native", "-debug.mpvSmokeStartOver", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.otherElements["player.native"].waitForExistence(timeout: 40), "native player did not appear")
        XCTAssertTrue(waitNative(app, timeout: 40) { (Double($0["pos"] ?? "") ?? 0) > 1 },
                      "native playback never started: \(nativeProbeText(app))")
        return app
    }

    func nativeProbeText(_ app: XCUIApplication) -> String {
        let el = app.descendants(matching: .any)["debug_nativeProbe"]
        guard el.waitForExistence(timeout: 5) else { return "" }
        return el.label
    }

    func nativeProbe(_ app: XCUIApplication) -> [String: String] {
        Self.parse(nativeProbeText(app))
    }

    func waitNative(_ app: XCUIApplication, timeout: TimeInterval = 5, _ cond: ([String: String]) -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond(nativeProbe(app)) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return cond(nativeProbe(app))
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    // MARK: Shared panel helpers

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Opens the panel with Down and walks Right until the Playback tab is selected.
    func openPlaybackTab(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        remote.press(.down)
        let tab = element(app, "player.panel.tab.playback")
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "no Playback tab", file: file, line: line)
        for _ in 0..<6 where (tab.value as? String) != "selected" {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(tab.value as? String, "selected", "never reached the Playback tab", file: file, line: line)
    }

    /// Geometric focus walk: presses Down/Up/Left/Right toward `target` until it has focus.
    /// Never presses Up from a row level with or above the target (that would leave the content
    /// section for the tab row).
    @discardableResult
    func focusWalk(_ app: XCUIApplication, to target: XCUIElement, maxSteps: Int = 24) -> Bool {
        for _ in 0..<maxSteps {
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
            guard focused.exists else { remote.press(.down); Thread.sleep(forTimeInterval: 0.4); continue }
            let f = focused.frame, t = target.frame
            if f.midY < t.minY - 4 {
                remote.press(.down)
            } else if f.midY > t.maxY + 4 {
                remote.press(.up)
            } else if f.midX < t.midX {
                remote.press(.right)
            } else {
                remote.press(.left)
            }
            Thread.sleep(forTimeInterval: 0.45)
        }
        return target.hasFocus
    }

    // MARK: mpv regression (A step 1)

    /// Regression only: the mpv Playback tab keeps its speed row, Timing and Diagnostics after the
    /// columns moved into `PlayerPlaybackColumns.swift`. It also passed before the extraction; it
    /// guards the move. Picking 1.25 marks that button selected.
    func testMpvPlaybackTabUnchanged() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PLAYER_BAR_PROBE"] == "1", "PLAYER_BAR_PROBE not set")
        let url = try XCTUnwrap(env["PLAYER_SMOKE_URL"], "PLAYER_SMOKE_URL not set")
        let app = XCUIApplication()
        app.launchArguments += ["-debug.mpvSmokeURL", url, "-player.nativeDolbyVision", "NO",
                                "-player.bufferMB", "8", "-debug.mpvSmokeStartOver", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["player.mpv"].waitForExistence(timeout: 30), "player did not appear")
        // Same start gate as the P1 harness: playback has really started (pos > 1).
        let seek = element(app, "debug_seekProbe")
        XCTAssertTrue(seek.waitForExistence(timeout: 30), "no seek probe")
        let started = Date().addingTimeInterval(30)
        while Date() < started, (Double(Self.parse(seek.label)["pos"] ?? "") ?? 0) <= 1 { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertGreaterThan(Double(Self.parse(seek.label)["pos"] ?? "") ?? 0, 1, "playback never started: \(seek.label)")
        let bar = element(app, "debug_transportProbe")
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "no transport probe")
        let end = Date().addingTimeInterval(20)
        while Date() < end, Self.parse(bar.label)["vis"] != "0" { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(Self.parse(bar.label)["vis"], "0", "bar never hid: \(bar.label)")

        openPlaybackTab(app)
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0] {
            XCTAssertTrue(element(app, "player.panel.speed.\(speed)").waitForExistence(timeout: 3), "no speed \(speed)")
        }
        XCTAssertTrue(element(app, "player.panel.diagnostics").exists, "no Diagnostics row")
        XCTAssertTrue(app.staticTexts["Audio Delay"].exists, "no Audio Delay row")
        XCTAssertEqual(element(app, "player.panel.speed.1.0").value as? String, "selected", "1x is not ticked")
        let target = element(app, "player.panel.speed.1.25")
        XCTAssertTrue(focusWalk(app, to: target), "focus never reached 1.25x")
        remote.press(.select)
        let end2 = Date().addingTimeInterval(4)
        while Date() < end2, (target.value as? String) != "selected" { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(target.value as? String, "selected", "1.25x not selected after the pick")
        print("[ParityLeg] mpv tab: \(seek.label) | \(bar.label)")
    }

    // MARK: Native legs (A step 6)

    /// Lets the start-of-playback transport bar hide (or gives up after `timeout`), so a Down
    /// press starts from the same state the viewer usually has.
    func waitBarSettled(_ app: XCUIApplication, timeout: TimeInterval = 10) {
        _ = waitNative(app, timeout: timeout) { $0["bar"] == "0" }
    }

    /// A8: the Playback tab's speed row drives the live rate through `selectSpeed`, and the tab
    /// re-reads the player's speed when the panel opens again. Fails before P4 (no Playback tab).
    func testNativePlaybackTabSpeed() throws {
        let app = try launchNative()
        waitBarSettled(app)
        openPlaybackTab(app)
        XCTAssertEqual(element(app, "player.panel.speed.1.0").value as? String, "selected",
                       "1x not ticked on open: \(nativeProbeText(app))")
        let target = element(app, "player.panel.speed.1.5")
        XCTAssertTrue(target.waitForExistence(timeout: 3), "no 1.5x button")
        XCTAssertTrue(focusWalk(app, to: target), "focus never reached 1.5x")
        remote.press(.select)
        XCTAssertTrue(waitNative(app, timeout: 4) { $0["speed"] == "1.5" }, "rate never became 1.5: \(nativeProbeText(app))")
        remote.press(.menu)
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element(app, "player.panel"))],
                                        timeout: 5), .completed, "panel did not close")
        try requireNativeStillPresented(app)
        waitBarSettled(app, timeout: 8)
        openPlaybackTab(app)
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        XCTAssertEqual(target.value as? String, "selected", "1.5x not ticked on re-open")
        XCTAssertTrue(waitNative(app, timeout: 2) { $0["speed"] == "1.5" }, nativeProbeText(app))
        print("[ParityLeg] native speed: \(nativeProbeText(app))")
    }

    /// A8: the native Playback tab carries the shared Sources column (`canSwitchStreams`: the smoke
    /// presenter has `onPlayNext`). Fails before P4 (no Playback tab on native).
    func testNativeSourcesColumnPresent() throws {
        let app = try launchNative()
        waitBarSettled(app)
        openPlaybackTab(app)
        XCTAssertTrue(app.staticTexts["SOURCES"].waitForExistence(timeout: 5), "no Sources caption")
        // The column itself is the oracle: its empty line, its loading spinner or a source row
        // (the smoke video id's add-on fetch may still be running on the fixture).
        let settled = app.staticTexts["No alternate sources found yet."].waitForExistence(timeout: 8)
        XCTAssertTrue(settled || app.activityIndicators.count > 0 || app.staticTexts["Switching resumes from your last saved position."].exists,
                      "the Sources column has no body: \(nativeProbeText(app))")
        XCTAssertTrue(app.staticTexts["Switching resumes from your last saved position."].exists, "no Sources footer")
        print("[ParityLeg] native sources settled=\(settled ? 1 : 0)")
        XCTAssertTrue(app.staticTexts["PLAYBACK SPEED"].exists, "no speed caption")
        print("[ParityLeg] native sources: \(nativeProbeText(app))")
    }

    /// D5: the transport bar's Sources menu item opens the app panel on the Playback tab. Fails
    /// before P4 (no custom menu items).
    func testNativeMenuItemOpensSources() throws {
        let app = try launchNative()
        waitBarSettled(app)
        remote.press(.select)                       // raise the bar
        XCTAssertTrue(waitNative(app, timeout: 4) { $0["bar"] == "1" }, "bar did not show: \(nativeProbeText(app))")
        // tvOS 26 draws the custom menu items as cells in the bar's top-right row, left of the
        // speed pill and the Subtitles / Audio cells; Up from the scrubber lands on the first one.
        let item = app.cells["Sources"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no Sources item in the transport bar")
        XCTAssertTrue(app.cells["Playback Speed"].exists, "no system speed pill (playerVC.speeds)")
        for _ in 0..<4 where !item.hasFocus {
            remote.press(.up)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(item.hasFocus || focusWalk(app, to: item, maxSteps: 8), "focus never reached the Sources item")
        remote.press(.select)
        XCTAssertTrue(element(app, "player.panel").waitForExistence(timeout: 6), "the panel did not open")
        let tab = element(app, "player.panel.tab.playback")
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "no Playback tab")
        XCTAssertEqual(tab.value as? String, "selected", "the panel did not open on Playback")
        print("[ParityLeg] native menu item: \(nativeProbeText(app))")
    }

    /// B16: the pause card never draws over a visible transport bar; once the bar is known hidden
    /// while paused it shows within 2 s, and one press hides it. If the simulator's bar never hides
    /// while paused, the leg skips (it must not pass vacuously, [C-19]).
    func testNativePauseCard() throws {
        let app = try launchNative()
        waitBarSettled(app)
        remote.press(.playPause)
        XCTAssertTrue(waitNative(app, timeout: 4) { $0["paused"] == "1" }, "did not pause: \(nativeProbeText(app))")
        var sawBarHidden: Date?
        var cardShownAt: Date?
        let end = Date().addingTimeInterval(12)
        while Date() < end {
            let p = nativeProbe(app)
            if p["card"] == "1" {
                XCTAssertEqual(p["bar"], "0", "card drawn while the bar is not known hidden: \(nativeProbeText(app))")
                cardShownAt = cardShownAt ?? Date()
            }
            if p["bar"] == "0", p["paused"] == "1" { sawBarHidden = sawBarHidden ?? Date() }
            if cardShownAt != nil { break }
            if let hidden = sawBarHidden, Date().timeIntervalSince(hidden) > 2 { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard sawBarHidden != nil else {
            throw XCTSkip("sim bar never hides while paused: \(nativeProbeText(app))")
        }
        XCTAssertNotNil(cardShownAt, "bar hidden while paused but no card within 2 s: \(nativeProbeText(app))")
        remote.press(.up)
        XCTAssertTrue(waitNative(app, timeout: 3) { $0["card"] == "0" }, "a press did not hide the card: \(nativeProbeText(app))")
        print("[ParityLeg] native pause card: \(nativeProbeText(app))")
    }

    /// Menu on the simulator can dismiss the cover even when consumed (see PlayerTransportUITests).
    func requireNativeStillPresented(_ app: XCUIApplication) throws {
        if !app.otherElements["player.native"].waitForExistence(timeout: 2) {
            throw XCTSkip("the simulator dismissed the native player on Menu (environmental)")
        }
    }
}
