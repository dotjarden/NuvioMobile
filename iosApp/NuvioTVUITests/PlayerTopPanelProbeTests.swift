import XCTest

/// Optional hardware/simulator attach probe. Open the shared Settings drawer before running.
/// Automated launch, navigation and real track selection are covered by LiveTVExperienceTests.
final class PlayerTopPanelProbeTests: XCTestCase {
    func testProbeBottomDrawer() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PLAYER_PANEL_PROBE"] == "1")
        let app = XCUIApplication()
        app.activate()
        let audio = app.buttons["player.panel.tab.audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 5), "Open the player's Settings drawer first")
        for tab in ["audio", "subtitles", "playback", "info"] {
            let button = app.buttons["player.panel.tab.\(tab)"]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThan(button.frame.minY, app.frame.height / 3)
            XCTAssertLessThan(button.frame.maxY, app.frame.height)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shared bottom drawer"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCUIRemote.shared.press(.menu)
        XCTAssertFalse(audio.exists)
        XCTAssertTrue(app.otherElements["player.native"].exists || app.otherElements["player.mpv"].exists)
    }
}
