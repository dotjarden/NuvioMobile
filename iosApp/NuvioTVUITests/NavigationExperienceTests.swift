import XCTest

final class NavigationExperienceTests: XCTestCase {
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
