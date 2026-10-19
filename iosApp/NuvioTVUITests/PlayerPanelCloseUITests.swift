import XCTest

/// BUG-186 legs on the mpv smoke rig: a Menu that lands while the top panel is still being
/// presented (or right after a swipe-up started its dismiss) used to latch the panel host's
/// `closing` flag with the panel left on screen, so every later Menu was swallowed and the player
/// could not be left. In both legs the panel must be gone within 2 s, and the next Menu must exit
/// the player. Skipped unless `PLAYER_BAR_PROBE=1` and `PLAYER_SMOKE_URL` are in the environment
/// (pass them as `TEST_RUNNER_*`).
final class PlayerPanelCloseUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    private func launch(extra: [String] = []) throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PLAYER_BAR_PROBE"] == "1", "PLAYER_BAR_PROBE not set")
        let url = try XCTUnwrap(env["PLAYER_SMOKE_URL"], "PLAYER_SMOKE_URL not set")
        let app = XCUIApplication()
        app.launchArguments += ["-debug.mpvSmokeURL", url, "-player.nativeDolbyVision", "NO",
                                "-debug.mpvSmokeStartOver", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.otherElements["player.mpv"].waitForExistence(timeout: 30), "player did not appear")
        let seek = app.descendants(matching: .any)["debug_seekProbe"]
        XCTAssertTrue(seek.waitForExistence(timeout: 30), "no seek probe")
        let started = Date().addingTimeInterval(30)
        while Date() < started, Self.pos(seek.label) <= 1 { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertGreaterThan(Self.pos(seek.label), 1, "playback never started: \(seek.label)")
        return app
    }

    private static func pos(_ label: String) -> Double {
        for part in label.split(separator: " ") where part.hasPrefix("pos=") {
            return Double(part.dropFirst(4)) ?? 0
        }
        return 0
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)],
                                timeout: timeout) == .completed
    }

    /// Panel gone within 2 s, then a Menu leaves the player.
    private func assertClosesThenExits(_ app: XCUIApplication, _ leg: String) {
        let panel = app.otherElements["player.panel"]
        XCTAssertTrue(waitGone(panel, timeout: 2), "\(leg): panel still up 2 s after the close")
        let player = app.otherElements["player.mpv"]
        // The first Menu may already have left the player once the panel was gone.
        guard player.exists else { return }
        remote.press(.menu)
        if waitGone(player, timeout: 3) { return }
        // A visible transport bar takes one Menu to hide first; the swallowed-Menu bug ignores both.
        remote.press(.menu)
        XCTAssertTrue(waitGone(player, timeout: 4), "\(leg): Menu after the close did not exit the player")
    }

    /// Menu straight after the Down that presents the panel (inside the ~0.25 s present).
    func testMenuDuringPanelPresent() throws {
        let app = try launch()
        Thread.sleep(forTimeInterval: 4)   // let the start-of-playback bar hide
        remote.press(.down)
        let pressedAt = Date()
        remote.press(.menu)
        print("[BUG186Leg] Menu \(Int(Date().timeIntervalSince(pressedAt) * 1000)) ms after Down returned")
        // The panel may or may not have been drawn before the close; either way it must not stay.
        _ = app.otherElements["player.panel"].waitForExistence(timeout: 0.5)
        assertClosesThenExits(app, "menu-during-present")
    }

    /// Swipe up (Play/Pause under `-debug.panelSwipeUpForce`) then an immediate Menu.
    func testSwipeUpThenImmediateMenu() throws {
        let app = try launch(extra: ["-debug.panelSwipeUpForce", "YES"])
        Thread.sleep(forTimeInterval: 4)
        remote.press(.down)
        XCTAssertTrue(app.otherElements["player.panel"].waitForExistence(timeout: 5), "panel did not present on Down")
        remote.press(.playPause)
        remote.press(.menu)
        assertClosesThenExits(app, "swipe-up-then-menu")
    }
}
