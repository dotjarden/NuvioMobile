import XCTest

/// Batch P (FEAT-82, Steven rc10): with Poster > Corners = Square every icon-only Detail action
/// button is one equal square whose side is Play's height. Reaches Square on the fixture through
/// `-debug.posterCornersOverride square` (Corners is a synced setting). Needs the identifiers the
/// DetailView hunks add: `detail_action_play`, `detail_action_trailer`, `detail_action_watched`,
/// `detail_action_library`, `detail_action_shuffle` (`detail_start_over` already exists).
///
/// The buttons are read by frame, so the legs prove the equal-square layout; whether the `.glass`
/// chrome honours the fixed frame on tvOS 26 is exactly what the first run answers.
final class DetailActionSquareUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Classic Home -> the hero CTA route into Detail, Cinematic layout (icon-only secondaries).
    private func launchToDetail(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-home_layout", "classic", "-detail_layout", "cinematic"] + extraArguments
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the sim session still signed in?")
        if !chris.hasFocus { press(.left, times: 3, gap: 0.5) }
        remote.press(.select)
        pause(10) // Home catalog fan-out
        press(.up, times: 6, gap: 0.5)
        press(.down, times: 1)
        pause(2)
        remote.press(.select)
        pause(6)
        return app
    }

    private static let iconIDs = ["detail_start_over", "detail_action_trailer", "detail_action_watched",
                                  "detail_action_library", "detail_action_shuffle"]

    private func frames(_ app: XCUIApplication) -> (play: CGRect?, icons: [(String, CGRect)]) {
        let play = app.buttons["detail_action_play"]
        let playFrame: CGRect? = play.waitForExistence(timeout: 20) ? play.frame : nil
        var icons: [(String, CGRect)] = []
        for id in Self.iconIDs {
            let element = app.buttons[id]
            if element.exists { icons.append((id, element.frame)) }
        }
        return (playFrame, icons)
    }

    /// Square corners: every icon button is width == height == Play's height (+-1), and all equal.
    func testSquareIconButtonsMatchPlayHeight() throws {
        let app = launchToDetail(extraArguments: ["-debug.posterCornersOverride", "square"])
        let (play, icons) = frames(app)
        shot("fe82_square")
        let playFrame = try XCTUnwrap(play, "Play button never appeared on Detail")
        XCTAssertFalse(icons.isEmpty, "no icon-only action buttons found")
        for (id, frame) in icons {
            print("[FEAT82] \(id) \(frame) play \(playFrame)")
            XCTAssertEqual(frame.width, frame.height, accuracy: 1, "\(id) is not square")
            XCTAssertEqual(frame.width, playFrame.height, accuracy: 1, "\(id) side != Play's height")
        }
        if let first = icons.first {
            for (id, frame) in icons {
                XCTAssertEqual(frame.width, first.1.width, accuracy: 1, "\(id) width differs from \(first.0)")
            }
        }
    }

    /// Default corners (Rounded): the capsule layout is untouched, so the trailer button (the wide
    /// `play.rectangle.fill`) is not square. Proves the knob, not a regression, drives the change.
    func testRoundedKeepsCapsules() throws {
        let app = launchToDetail(extraArguments: ["-debug.posterCornersOverride", "rounded"])
        let (play, icons) = frames(app)
        shot("fe82_rounded")
        XCTAssertNotNil(play, "Play button never appeared on Detail")
        guard let trailer = icons.first(where: { $0.0 == "detail_action_trailer" }) else {
            throw XCTSkip("this title has no trailer button")
        }
        XCTAssertNotEqual(trailer.1.width, trailer.1.height, accuracy: 1)
    }
}
