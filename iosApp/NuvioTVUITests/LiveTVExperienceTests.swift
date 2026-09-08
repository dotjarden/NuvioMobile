import XCTest

final class LiveTVExperienceTests: XCTestCase {
    @MainActor private func select(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            let focusedMatch = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let focused: XCUIElement? = focusedMatch.exists ? focusedMatch : nil
            if target.hasFocus || (focused?.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) == true && (focused?.frame.width ?? 0) * (focused?.frame.height ?? 0) <= target.frame.width * target.frame.height * 1.5) {
                XCUIRemote.shared.press(.select)
                return
            }
            guard let focused else { XCUIRemote.shared.press(.down); continue }
            let dx = target.frame.midX - focused.frame.midX, dy = target.frame.midY - focused.frame.midY
            let direction: XCUIRemote.Button = abs(dy) > max(20, focused.frame.height / 2) ? (dy > 0 ? .down : .up) : (dx > 0 ? .right : .left)
            XCUIRemote.shared.press(direction)
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Could not focus \(target.label) using the remote")
    }
    @MainActor func testLivePlayerNativeMenuFocus() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--live-player-ui-test"]
        app.launch()
        let channel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Focus Test One")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 20))
        select(channel, in: app)
        Thread.sleep(forTimeInterval: 4)
        XCUIRemote.shared.press(.select)
        let menu = app.cells["Live TV"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), app.debugDescription)
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Next channel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Native Live TV menu"; shot.lifetime = .keepAlways; add(shot)
        select(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Next channel")).firstMatch, in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.select)
        select(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Channel guide")).firstMatch, in: app)
        XCTAssertTrue(app.buttons["Sources"].waitForExistence(timeout: 10))
    }

    @MainActor func testBrowseTypeSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--browse-ui-test"]
        app.launch()
        let menu = app.buttons["Browse: Movies"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        select(menu, in: app)
        let shows = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shows")).firstMatch
        XCTAssertTrue(shows.waitForExistence(timeout: 5))
        let dropdown = XCTAttachment(screenshot: app.screenshot())
        dropdown.name = "Anchored Browse dropdown"; dropdown.lifetime = .keepAlways; add(dropdown)
        select(shows, in: app)
        XCTAssertTrue(app.buttons["Browse: Shows"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Browse shows"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testSettingsCategorySelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--settings-ui-test"]
        app.launch()
        let title = app.staticTexts["settingsPaneTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "Playback")
        select(app.cells.containing(.button, identifier: "settings.category.appearance").firstMatch, in: app)
        XCTAssertEqual(title.label, "Appearance")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Settings layout"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testGuideAndNativeSourceManagement() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--live-tv-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Sources"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Fixture Nature")).firstMatch.waitForExistence(timeout: 45))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native Live TV guide"; screenshot.lifetime = .keepAlways; add(screenshot)
        select(app.buttons["Sources"], in: app)
        XCTAssertTrue(app.buttons["Add source"].waitForExistence(timeout: 10))
        select(app.buttons["Add source"], in: app)
        XCTAssertTrue(app.textFields["Source name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save and connect"].isEnabled)
        select(app.buttons["Save and connect"], in: app)
        XCTAssertTrue(app.staticTexts["sourceValidation"].waitForExistence(timeout: 5))
        let editorShot = XCTAttachment(screenshot: app.screenshot())
        editorShot.name = "Readable source editor"; editorShot.lifetime = .keepAlways; add(editorShot)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        select(app.buttons["Cancel"], in: app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        let existing = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Local test provider")).firstMatch
        select(existing, in: app)
        XCTAssertTrue(app.buttons["Save and connect"].waitForExistence(timeout: 5))
        select(app.buttons["Save and connect"], in: app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 30))
        select(app.buttons["Done"], in: app)
        XCTAssertTrue(app.buttons["Sources"].waitForExistence(timeout: 10))
    }
}

/// Opt-in integration check: contacts the real public service and creates a temporary pairing session.
final class AuthenticationConnectivityTests: XCTestCase {
    @MainActor func testOfficialServerCreatesQRCode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--qr-sign-in-ui-test"]
        app.launch()
        XCTAssertTrue(app.images["Sign-in QR code"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["Waiting for approval… this screen updates automatically."].exists)
        app.terminate()
    }
}
