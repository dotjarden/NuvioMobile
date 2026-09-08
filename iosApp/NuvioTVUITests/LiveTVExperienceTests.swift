import XCTest

final class LiveTVExperienceTests: XCTestCase {
    @MainActor private func select(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            let focusedMatch = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let focused: XCUIElement? = focusedMatch.exists ? focusedMatch : nil
            if target.hasFocus || focused?.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) == true {
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
    @MainActor func testBrowseTypeSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--browse-ui-test"]
        app.launch()
        let menu = app.buttons["Browse: Movies"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        select(menu, in: app)
        XCTAssertTrue(app.buttons["Shows"].waitForExistence(timeout: 5))
        select(app.buttons["Shows"], in: app)
        XCTAssertTrue(app.buttons["Browse: Shows"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Browse shows"; shot.lifetime = .keepAlways; add(shot)
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
