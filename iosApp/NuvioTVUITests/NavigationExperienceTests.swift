import XCTest

final class NavigationExperienceTests: XCTestCase {
    @MainActor func testHomeNavigationReturnsAfterScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sidebar_style", "tabs"]
        app.launch()
        let profiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'profiles.profile.'"))
        XCTAssertTrue(profiles.firstMatch.waitForExistence(timeout: 25))
        XCUIRemote.shared.press(.select)
        let home = app.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        for depth in [3, 5, 8] {
            for _ in 0..<16 {
                if home.hasFocus { break }
                XCUIRemote.shared.press(.up)
                Thread.sleep(forTimeInterval: 0.3)
            }
            XCTAssertTrue(home.hasFocus, "Home navigation must be reachable before the scroll")
            for _ in 0..<depth {
                XCUIRemote.shared.press(.down)
                Thread.sleep(forTimeInterval: 0.4)
            }
            XCTAssertFalse(home.hasFocus, "Down must leave the restored tab bar")
            XCTAssertTrue(app.staticTexts["debug_hero"].label.contains("foc=0"),
                          "Down must enter the shelves again, not remain stuck on the hero")
            let down = XCTAttachment(screenshot: app.screenshot())
            down.name = "Home down \(depth)"; down.lifetime = .keepAlways; add(down)
            for _ in 0..<(depth + 4) {
                if home.hasFocus { break }
                XCUIRemote.shared.press(.up)
                Thread.sleep(forTimeInterval: 0.4)
            }
            let up = XCTAttachment(screenshot: app.screenshot())
            up.name = "Home back up \(depth)"; up.lifetime = .keepAlways; add(up)
            XCTAssertTrue(home.hasFocus, "Up from Home's first shelf/hero must reach the tabs\n\(app.debugDescription)")
            XCTAssertGreaterThanOrEqual(home.frame.minY, 0)
        }
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.buttons["Search"].hasFocus, "Restored tabs must allow switching destinations")
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.textFields["search.query"].waitForExistence(timeout: 15))
    }

    @MainActor func testTabsRemainUsableAfterScrollingAndDetails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--navigation-layout-ui-test", "-sidebar_style", "tabs"]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 20))
        for name in ["Home", "Search", "Settings", "Search", "Home"] {
            // Return from content to navigation and verify the tab can actually take focus.
            for _ in 0..<20 {
                if ["Home", "Search", "Settings"].contains(where: { app.buttons[$0].hasFocus }) { break }
                remote.press(.up)
                Thread.sleep(forTimeInterval: 0.2)
            }
            let tab = app.buttons[name]
            for _ in 0..<3 {
                if tab.hasFocus { break }
                remote.press(.left)
            }
            for _ in 0..<3 {
                if tab.hasFocus { break }
                remote.press(.right)
            }
            XCTAssertTrue(tab.hasFocus, "Top navigation must receive remote focus: \(name)\n\(app.debugDescription)")
            XCTAssertGreaterThanOrEqual(tab.frame.minY, 0, "Tab must not be clipped above the screen")
            remote.press(.select)
            let link = app.buttons["nav.detail.\(name)"]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            for _ in 0..<16 { remote.press(.down) }
            XCTAssertTrue(app.buttons["nav.row.\(name).11"].hasFocus, "Exercise the entire scroll, not only the first row")
            for _ in 0..<20 {
                if tab.hasFocus { break }
                remote.press(.up)
            }
            XCTAssertTrue(tab.hasFocus, "Scrolling back up must restore reachable tabs")
            for _ in 0..<5 {
                if link.hasFocus { break }
                remote.press(.down)
            }
            XCTAssertTrue(link.hasFocus)
            remote.press(.select)
            XCTAssertTrue(app.buttons["detail.season"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertFalse(app.buttons["Search"].isHittable, "Immersive content must hide the root tabs")
            remote.press(.menu)
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 0.5)
        }
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Native tabs after repeated scroll and detail returns"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
