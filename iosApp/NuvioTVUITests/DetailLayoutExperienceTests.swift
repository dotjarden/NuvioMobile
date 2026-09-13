import XCTest

final class DetailLayoutExperienceTests: XCTestCase {
    @MainActor private func focus(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if target.hasFocus || (focused.exists && focused.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)) && focused.frame.width * focused.frame.height <= target.frame.width * target.frame.height * 1.5) { return }
            guard focused.exists else { XCUIRemote.shared.press(.down); continue }
            let dx = target.frame.midX - focused.frame.midX, dy = target.frame.midY - focused.frame.midY
            XCUIRemote.shared.press(abs(dy) > max(24, focused.frame.height / 2) ? (dy > 0 ? .down : .up) : (dx > 0 ? .right : .left))
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Could not focus \(target.identifier)\n\(app.debugDescription)")
    }

    @MainActor func testSeasonMenuAndInformationReading() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--detail-layout-ui-test"]
        app.launch()
        let season = app.buttons["detail.season"]
        XCTAssertTrue(season.waitForExistence(timeout: 20), app.debugDescription)
        let initial = XCTAttachment(screenshot: app.screenshot()); initial.name = "Content page overview"; initial.lifetime = .keepAlways; add(initial)
        focus(season, in: app); XCUIRemote.shared.press(.select)
        let second = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Season 2")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 5), app.debugDescription)
        focus(second, in: app); XCUIRemote.shared.press(.select)
        let episode = app.buttons["detail.episode.s2e1"]
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        focus(episode, in: app)
        let episodes = XCTAttachment(screenshot: app.screenshot()); episodes.name = "Single season selector and episode shelf"; episodes.lifetime = .keepAlways; add(episodes)
        // Up returns to the selector and opens its native menu again.
        focus(season, in: app); XCUIRemote.shared.press(.select)
        let specials = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Specials")).firstMatch
        XCTAssertTrue(specials.waitForExistence(timeout: 5))
        focus(specials, in: app); XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["detail.episode.special"].waitForExistence(timeout: 5))

        let paragraphs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'detail.about.'"))
        XCTAssertGreaterThanOrEqual(paragraphs.count, 2)
        let lastParagraph = paragraphs.element(boundBy: paragraphs.count - 1)
        focus(lastParagraph, in: app)
        let firstParagraph = app.descendants(matching: .any)["detail.about.0"]
        focus(firstParagraph, in: app)
        let guide = app.descendants(matching: .any)["detail.parental.0"]
        XCTAssertTrue(guide.exists)
        XCTAssertGreaterThan(guide.frame.minX, firstParagraph.frame.maxX, "About and parental information have separate columns")
        let reading = XCTAttachment(screenshot: app.screenshot()); reading.name = "About and parental guide columns"; reading.lifetime = .keepAlways; add(reading)
        focus(guide, in: app)
        focus(app.descendants(matching: .any)["detail.parental.2"], in: app)
        focus(guide, in: app)
    }
}
