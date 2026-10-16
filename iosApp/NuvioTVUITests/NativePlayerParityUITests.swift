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
final class NativePlayerParityUITests: XCTestCase {
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
        print("[ParityLeg] mpv tab: \(bar.label)")
    }
}
