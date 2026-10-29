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

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Into Detail by the shared, fixture-independent Search route (`DetailEntryRoute`), Cinematic
    /// layout (icon-only secondaries) unless a leg asks for Classic. Classic Home stays pinned for
    /// the route's verified hero-CTA fallback.
    private func launchToDetail(extraArguments: [String], detailLayout: String = "cinematic") -> XCUIApplication {
        DetailEntryRoute.launchToDetail(self, arguments: ["-home_layout", "classic", "-detail_layout", detailLayout] + extraArguments)
    }

    private static let iconIDs = ["detail_start_over", "detail_action_trailer", "detail_action_watched",
                                  "detail_action_library", "detail_action_shuffle"]

    /// A focused button's XCUI frame includes the focus effect's outset (FA87, 2026-10-22: +4 pt a
    /// side, so a 72 pt square reads 80 × 80 at 4 pt above its neighbours). Frames compared across
    /// focus states may differ by up to this much; frames in the same state must match to 1 pt.
    private static let focusLift: CGFloat = 12

    private func frames(_ app: XCUIApplication) -> (play: CGRect?, icons: [(String, CGRect, Bool)]) {
        let play = app.buttons["detail_action_play"]
        let playFrame: CGRect? = play.waitForExistence(timeout: 20) ? play.frame : nil
        var icons: [(String, CGRect, Bool)] = []
        for id in Self.iconIDs {
            let element = app.buttons[id]
            if element.exists { icons.append((id, element.frame, element.hasFocus)) }
        }
        return (playFrame, icons)
    }

    /// Square corners: every icon button is width == height == Play's height (+-1), and all equal.
    /// The one focused button (Play, or the first enabled icon when Play is disabled, as on the
    /// FA87 fixture's "Playback unavailable" series) reads lifted by the focus outset, so it is
    /// held to square plus the lift; buttons in the same focus state as Play match it to 1 pt.
    func testSquareIconButtonsMatchPlayHeight() throws {
        let app = launchToDetail(extraArguments: ["-debug.posterCornersOverride", "square"])
        let (play, icons) = frames(app)
        let playFocused = app.buttons["detail_action_play"].hasFocus
        shot("fe82_square")
        let playFrame = try XCTUnwrap(play, "Play button never appeared on Detail")
        XCTAssertFalse(icons.isEmpty, "no icon-only action buttons found")
        for (id, frame, focused) in icons {
            print("[FEAT82] \(id) \(frame) focused=\(focused) play \(playFrame) playFocused=\(playFocused)")
            XCTAssertEqual(frame.width, frame.height, accuracy: 1, "\(id) is not square")
            let delta = frame.width - playFrame.height
            if focused == playFocused {
                XCTAssertEqual(delta, 0, accuracy: 1, "\(id) side != Play's height")
            } else if focused {
                XCTAssertTrue((-1...Self.focusLift).contains(delta), "\(id) (focused) side \(frame.width) vs Play \(playFrame.height)")
            } else {
                XCTAssertTrue((-Self.focusLift...1).contains(delta), "\(id) side \(frame.width) vs focused Play \(playFrame.height)")
            }
        }
        let resting = icons.filter { !$0.2 }
        if let first = resting.first {
            for (id, frame, _) in resting {
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

    /// Review r1 P1-1 / P3-11: Classic Detail with Icons Only off draws text labels, so the
    /// secondaries keep their natural (wider than tall) width in Square and Play is unchanged
    /// from a Rounded launch.
    func testClassicTextButtonsKeepNaturalWidthInSquare() throws {
        // Review r2 P3-3: pin Icons Only OFF (a local AppStorage value the fixture may carry).
        let rounded = launchToDetail(extraArguments: ["-debug.posterCornersOverride", "rounded", "-detail_action_icons_only", "NO"],
                                     detailLayout: "classic")
        let roundedPlay = try XCTUnwrap(frames(rounded).play, "Play never appeared (Rounded, Classic)")
        rounded.terminate()
        let app = launchToDetail(extraArguments: ["-debug.posterCornersOverride", "square", "-detail_action_icons_only", "NO"],
                                 detailLayout: "classic")
        let (play, _) = frames(app)
        shot("fe82_classic_square_text")
        // Same-launch check that needs no second title: Play itself is never squared.
        if let play { XCTAssertGreaterThan(play.width, play.height + 20, "Play was squared on Classic") }
        let playFrame = try XCTUnwrap(play, "Play never appeared (Square, Classic)")
        let watched = app.buttons["detail_action_watched"]
        XCTAssertTrue(watched.waitForExistence(timeout: 20), "Mark Watched button never appeared")
        XCTAssertGreaterThan(watched.frame.width, watched.frame.height + 20,
                             "a text button must keep its natural width, not be squared")
        XCTAssertEqual(playFrame.width, roundedPlay.width, accuracy: 2, "Play's width changed under Square")
    }

    /// Classic + Icons Only on: Play is icon-only too and must keep its own width, not stretch to fill the row.
    func testClassicIconsOnlyKeepsPlayWidthInSquare() throws {
        let app = launchToDetail(extraArguments: ["-debug.posterCornersOverride", "square", "-detail_action_icons_only", "YES"],
                                 detailLayout: "classic")
        let (play, _) = frames(app)
        shot("fe82_classic_square_icons")
        let playFrame = try XCTUnwrap(play, "Play never appeared (Square, Classic, Icons Only)")
        XCTAssertLessThan(playFrame.width, app.frame.width / 2, "Play stretched across the action row")
    }
}
