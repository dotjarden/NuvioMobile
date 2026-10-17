import XCTest

/// Focus consistency (`.focusRow()`): every row of the profile editor is one full-width focus
/// section, so Up/Down from any control reaches the next row. Before the fix, Down from the
/// rightmost colour swatch found nothing (Save is narrower and centred) and focus stayed put.
///
/// FA87 fixture (tvOS 26.5, `hasFocus` works). Opens Add Profile (no profile is created: the leg
/// leaves with Menu) so the fixture's own profiles are never edited.
final class FocusRowUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func poll(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            pause(0.2)
        }
        return condition()
    }

    private func focusedSwatch(_ app: XCUIApplication) -> String? {
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profileEdit.swatch."))
        for index in 0..<swatches.count {
            let swatch = swatches.element(boundBy: index)
            if swatch.hasFocus { return swatch.identifier }
        }
        return nil
    }

    func testProfileEditorDownFromRightmostSwatchReachesSave() {
        let app = XCUIApplication()
        app.launchArguments = ["-debug.rememberLastProfile", "NO"]
        app.launch()

        let addProfile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Profile")).firstMatch
        XCTAssertTrue(addProfile.waitForExistence(timeout: 90), "profile picker never appeared — is the FA87 fixture set up?")
        // Walk right to the Add Profile tile (last in the row).
        for _ in 0..<8 where !addProfile.hasFocus {
            remote.press(.right)
            pause(0.5)
        }
        XCTAssertTrue(addProfile.hasFocus, "could not reach Add Profile")
        remote.press(.select)

        let save = app.buttons["profileEdit.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "editor never opened")
        pause(1.5)

        // Down until a colour swatch holds focus (the avatar strip may sit between).
        for _ in 0..<4 where focusedSwatch(app) == nil {
            remote.press(.down)
            pause(0.6)
        }
        XCTAssertNotNil(focusedSwatch(app), "Down never reached the colour swatches")

        // To the rightmost swatch.
        for _ in 0..<9 {
            remote.press(.right)
            pause(0.4)
        }
        XCTAssertEqual(focusedSwatch(app), "profileEdit.swatch.#5E35B1", "not on the rightmost swatch")

        remote.press(.down)
        XCTAssertTrue(poll(3) { save.hasFocus }, "Down from the rightmost swatch did not reach Save")

        remote.press(.up)
        XCTAssertTrue(poll(3) { self.focusedSwatch(app) != nil }, "Up from Save did not return to the swatches")

        remote.press(.menu)
        pause(1)
    }
}
