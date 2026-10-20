import XCTest

/// Batch P (BUG-193, Steven rc10): the full-synopsis screen draws the page's own backdrop under a
/// flat dark scrim (no material, no blur), and Menu still closes it with Detail on screen (the F8
/// regression: a clear presentation background once let one Menu dismiss the cover AND pop Detail).
/// The backdrop carries the DEBUG identifier `detail_synopsis_backdrop`; it needs the
/// `backdropURL:` hunk in DetailView.swift to be applied.
final class DetailSynopsisSheetUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSheetDrawsTheBackdropNotAMaterial() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-debug.openDeepLink", "nuviotv://title?id=tt0903747&type=series&name=Breaking%20Bad",
                                "-detail_layout", "cinematic"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        if chris.waitForExistence(timeout: 90) {
            remote.press(.left); pause(0.5); remote.press(.left); pause(0.5); remote.press(.select)
        }
        // Review r2 P3-4: the teaser id sits on both the truncated BUTTON and the plain text; only
        // the button proves the synopsis is truncated (Select on plain text would land on Play).
        let teaser = app.buttons["detail_synopsis_teaser"]
        // Review r1 P3-10: no skips. The tvOS 27 simulator never reports `hasFocus`, so the climb is a
        // fixed four Ups from the hero; the assertions below are on existence, so a wrong landing
        // (Select on Play, which opens the player instead of the sheet) FAILS instead of skipping.
        // Breaking Bad's synopsis is long enough to be truncated, so the teaser must exist.
        XCTAssertTrue(teaser.waitForExistence(timeout: 30), "no synopsis teaser on the Breaking Bad fixture")
        for _ in 0..<4 {
            remote.press(.up)
            pause(0.8)
        }
        remote.press(.select)
        let sheet = app.descendants(matching: .any)["detail_synopsis_sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "Select on the teaser must open the synopsis sheet (a miss means focus never reached the teaser)")
        pause(1.5)
        shot("bug193-sheet")
        XCTAssertTrue(app.descendants(matching: .any)["detail_synopsis_backdrop"].exists,
                      "the sheet must draw the page's backdrop (DEBUG identifier detail_synopsis_backdrop)")
        remote.press(.menu)
        pause(2)
        XCTAssertFalse(sheet.exists, "Menu must close the synopsis sheet")
        XCTAssertTrue(app.descendants(matching: .any)["detail_hero"].exists,
                      "Detail must still be up after one Menu press (F8)")
    }
}
