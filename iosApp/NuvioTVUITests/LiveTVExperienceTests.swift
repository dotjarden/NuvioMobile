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
        XCTFail("Could not focus \(target.label) using the remote\n\(app.debugDescription)")
    }
    @MainActor private func openNativeDrawer(_ app: XCUIApplication) {
        XCUIRemote.shared.press(.select)
        let settings = app.cells["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        // AVKit exposes its focused playback surface as a full-screen accessibility element.
        // Up enters its custom transport action, then Select opens the Settings menu.
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.select)
        let playback = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback")).firstMatch
        XCTAssertTrue(playback.waitForExistence(timeout: 5), app.debugDescription)
        select(playback, in: app)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func verifyDrawer(_ app: XCUIApplication) {
        let audio = app.buttons["player.panel.tab.audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(audio.frame.minY, 350, "Player tabs must be in the bottom drawer")
        select(audio, in: app)
        XCTAssertEqual(audio.value as? String, "selected")
        select(app.buttons["player.panel.tab.subtitles"], in: app)
        XCTAssertEqual(app.buttons["player.panel.tab.subtitles"].value as? String, "selected")
        select(app.buttons["player.panel.tab.info"], in: app)
        XCTAssertEqual(app.buttons["player.panel.tab.info"].value as? String, "selected")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Shared bottom player Details"; shot.lifetime = .keepAlways; add(shot)
        select(app.buttons["player.panel.tab.playback"], in: app)
    }

    @MainActor private func verifyMovieControls(_ app: XCUIApplication) {
        select(app.buttons["player.panel.tab.audio"], in: app)
        let audio = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'player.panel.audio.' AND identifier != 'player.panel.audio.route'"))
        XCTAssertGreaterThanOrEqual(audio.count, 2)
        select(audio.element(boundBy: 1), in: app)
        XCTAssertEqual(audio.element(boundBy: 1).value as? String, "selected")
        select(app.buttons["player.panel.tab.subtitles"], in: app)
        let subtitles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'player.panel.subtitle.' AND identifier != 'player.panel.subtitle.off'"))
        XCTAssertGreaterThan(subtitles.count, 0)
        select(subtitles.element(boundBy: 0), in: app)
        XCTAssertEqual(subtitles.element(boundBy: 0).value as? String, "selected")
        select(app.buttons["player.panel.subtitle.off"], in: app)
        XCTAssertEqual(app.buttons["player.panel.subtitle.off"].value as? String, "selected")
        select(app.buttons["player.panel.tab.playback"], in: app)
        select(app.buttons["player.panel.speed"], in: app)
        let speed = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "1.5×")).firstMatch
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        select(speed, in: app)
        XCTAssertEqual(app.buttons["player.panel.speed"].value as? String, "1.5×")
        let drawerInteractive = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"),
                                                        object: app.buttons["player.panel.tab.playback"])
        XCTAssertEqual(XCTWaiter.wait(for: [drawerInteractive], timeout: 5), .completed)
    }

    @MainActor func testLivePlayerNativeMenuFocus() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--live-player-ui-test"]
        app.launch()
        let channel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Focus Test One")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 20))
        select(channel, in: app)
        Thread.sleep(forTimeInterval: 5)
        openNativeDrawer(app)
        verifyDrawer(app)
        select(app.buttons["Next channel"], in: app)
        Thread.sleep(forTimeInterval: 2)
        openNativeDrawer(app)
        select(app.buttons["Channel guide"], in: app)
        XCTAssertTrue(app.buttons["Sources"].waitForExistence(timeout: 10))
    }

    @MainActor func testNativeMovieBottomDrawer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--native-player-ui-test"]
        app.launch()
        XCTAssertTrue(app.otherElements["player.native"].waitForExistence(timeout: 60), app.debugDescription)
        Thread.sleep(forTimeInterval: 3)
        openNativeDrawer(app)
        verifyDrawer(app)
        verifyMovieControls(app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["player.native"].exists)
    }

    @MainActor func testMPVMovieBottomDrawer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--mpv-player-ui-test"]
        app.launch()
        XCTAssertTrue(app.otherElements["player.mpv"].waitForExistence(timeout: 30))
        XCUIRemote.shared.press(.playPause)
        let settings = app.buttons["player.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        select(settings, in: app)
        let playback = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback")).firstMatch
        XCTAssertTrue(playback.waitForExistence(timeout: 5), app.debugDescription)
        select(playback, in: app)
        verifyDrawer(app)
        verifyMovieControls(app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["player.mpv"].exists)
    }

    private func playbackSeconds(_ label: String) -> Int {
        label.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor func testCompactPanelLongTrackLists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--player-panel-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["player.panel.tab.audio"].waitForExistence(timeout: 20))
        let lastAudio = app.buttons["player.panel.audio.20"]
        select(lastAudio, in: app)
        XCTAssertEqual(lastAudio.value as? String, "selected")
        XCTAssertTrue(lastAudio.isHittable, "The final audio track must remain reachable in a compact panel")
        select(app.buttons["player.panel.tab.subtitles"], in: app)
        let lastSubtitle = app.buttons["player.panel.subtitle.20"]
        select(lastSubtitle, in: app)
        XCTAssertEqual(lastSubtitle.value as? String, "selected")
        XCTAssertTrue(lastSubtitle.isHittable)
        select(app.buttons["player.panel.subtitleDelay.plus"], in: app)
        XCTAssertEqual(app.staticTexts["player.panel.subtitleDelay.value"].label, "+0.10 s")
        select(app.buttons["player.panel.subtitleDelay.reset"], in: app)
        XCTAssertEqual(app.staticTexts["player.panel.subtitleDelay.value"].label, "+0.00 s")
        let timingRemainsVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true AND isHittable == true"),
                                                           object: app.buttons["player.panel.subtitleDelay.plus"])
        XCTAssertEqual(XCTWaiter.wait(for: [timingRemainsVisible], timeout: 5), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Compact subtitle timing after long list"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testMPVTransportAfterDrawer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--mpv-player-ui-test"]
        app.launch()
        let playPause = app.buttons["player.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 20))
        let transportHeight = app.descendants(matching: .any)["player.timeline"].frame.maxY - playPause.frame.minY
        XCTAssertGreaterThan(transportHeight, 60, "The timeline belongs beneath the transport buttons")
        XCTAssertLessThan(transportHeight, 160, "Transport should remain a compact bottom control area")
        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "Compact MPV transport"; compact.lifetime = .keepAlways; add(compact)
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(playPause.label, "Play", "The remote Play/Pause button must pause exactly once")
        select(playPause, in: app)
        XCTAssertEqual(playPause.label, "Pause", "Select on Play must resume")
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(playPause.label, "Play")
        select(app.buttons["player.settings"], in: app)
        let playback = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback")).firstMatch
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        select(playback, in: app)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(playPause.label, "Pause", "Play/Pause must work after closing Settings")
        let elapsed = app.descendants(matching: .any)["player.timeline"]
        let previous = elapsed.value as? String ?? ""
        let advances = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previous), object: elapsed)
        XCTAssertEqual(XCTWaiter.wait(for: [advances], timeout: 4), .completed, "Playback time must continue updating after the drawer closes")
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(playPause.label, "Play")
        let timeline = app.descendants(matching: .any)["player.timeline"]
        XCTAssertTrue(timeline.exists, "The visible timeline must be focusable for seeking")
        // Move focus without selecting: Select on the timeline intentionally toggles playback.
        for _ in 0..<3 where !timeline.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(timeline.hasFocus, app.debugDescription)
        let beforeSeek = timeline.value as? String ?? ""
        XCUIRemote.shared.press(.right)
        let seeks = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", beforeSeek), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [seeks], timeout: 5), .completed, "Right on the timeline must change playback position")
        let forward = timeline.value as? String ?? ""
        XCUIRemote.shared.press(.left)
        let seeksBack = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", forward), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [seeksBack], timeout: 5), .completed)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(playPause.label, "Pause", "Select on the timeline must resume exactly once")
        let beforeHide = playbackSeconds(timeline.value as? String ?? "")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 6), .completed)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.playPause)
        Thread.sleep(forTimeInterval: 1)
        let afterHiddenSeek = playbackSeconds(timeline.value as? String ?? "")
        XCTAssertGreaterThan(afterHiddenSeek, beforeHide + 7, "Right must seek while the controls are hidden")
        XCTAssertLessThan(afterHiddenSeek, beforeHide + 25, "Releasing Right must stop repeat seeking")

    }

    @MainActor func testNativeTransportAfterDrawer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--native-player-ui-test"]
        app.launch()
        XCTAssertTrue(app.otherElements["player.native"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 2)
        openNativeDrawer(app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
        // The drawer must return control to AVKit's timeline, including repeated play/pause.
        XCUIRemote.shared.press(.playPause)
        let elapsed = app.otherElements["AXElapsedTime"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5), app.debugDescription)
        let first = elapsed.label
        Thread.sleep(forTimeInterval: 1.5)
        let initiallyPlaying = elapsed.label != first
        XCUIRemote.shared.press(.playPause)
        Thread.sleep(forTimeInterval: 0.5)
        let second = elapsed.label
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertNotEqual(elapsed.label != second, initiallyPlaying, "Play/Pause must change the actual playback state after closing the drawer")
        // Pause before seeking. Down enters the native scrubber from the transport action row.
        if !initiallyPlaying { XCUIRemote.shared.press(.playPause) }
        XCUIRemote.shared.press(.down)
        let beforeSeek = playbackSeconds(elapsed.label)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertGreaterThan(playbackSeconds(elapsed.label), beforeSeek + 5, app.debugDescription)
        XCTAssertTrue(app.otherElements["player.native"].exists)
    }

    @MainActor func testBrowseTypeSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--browse-ui-test"]
        app.launch()
        let menu = app.buttons["Browse: Movies"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        let filterY = menu.frame.midY
        select(menu, in: app)
        let shows = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shows")).firstMatch
        XCTAssertTrue(shows.waitForExistence(timeout: 5))
        let dropdown = XCTAttachment(screenshot: app.screenshot())
        dropdown.name = "Anchored Browse dropdown"; dropdown.lifetime = .keepAlways; add(dropdown)
        select(shows, in: app)
        XCTAssertTrue(app.buttons["Browse: Shows"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["Browse: Shows"].frame.midY, filterY, accuracy: 2)
        select(app.buttons["Genre: All genres"], in: app)
        let action = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Action")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        select(action, in: app)
        XCTAssertTrue(app.buttons["Genre: Action"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["Browse: Shows"].frame.midY, filterY, accuracy: 2)
        select(app.buttons["Reset"], in: app)
        XCTAssertTrue(app.buttons["Genre: All genres"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Browse shows"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testBrowseSharesPinnedHomeInteraction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let heroPredicate = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Go to Movie:", "Go to Show:")
        app.launchArguments = ["--home-ui-test", "-hero_nuvio_style", "YES"]
        app.launch()
        let homeHero = app.buttons.matching(heroPredicate).firstMatch
        XCTAssertTrue(homeHero.waitForExistence(timeout: 40))
        let homeShot = XCTAttachment(screenshot: app.screenshot())
        homeShot.name = "Home pinned baseline"; homeShot.lifetime = .keepAlways; add(homeShot)
        app.terminate()

        app.launchArguments = ["--browse-ui-test", "-hero_nuvio_style", "YES"]
        app.launch()
        let browseHero = app.buttons.matching(heroPredicate).firstMatch
        XCTAssertTrue(browseHero.waitForExistence(timeout: 40))
        let browseY = browseHero.frame.midY
        select(app.buttons["Browse: Movies"], in: app)
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(browseHero.frame.midY, browseY, accuracy: 2, "The hero must remain pinned while rows scroll")
        var reachedSeeAll = false
        for _ in 0..<25 {
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.label.localizedCaseInsensitiveContains("see all") { reachedSeeAll = true; break }
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(reachedSeeAll, "See All must be reachable at the end of the catalog row")
        Thread.sleep(forTimeInterval: 1)
        let browseShot = XCTAttachment(screenshot: app.screenshot())
        browseShot.name = "Browse pinned header and trailing See All"; browseShot.lifetime = .keepAlways; add(browseShot)
    }

    @MainActor func testFiltersSurviveScrollReturn() throws {
        verifyFiltersSurviveScrollReturn(largePosters: false)
    }
    @MainActor func testLargeBrowseFiltersSurviveScrollReturn() throws {
        verifyFiltersSurviveScrollReturn(largePosters: true)
    }
    @MainActor private func verifyFiltersSurviveScrollReturn(largePosters: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--browse-ui-test", "-hero_nuvio_style", "YES"]
        if largePosters { app.launchArguments.append("--large-posters") }
        app.launch()
        let filter = app.buttons["Browse: Movies"]
        XCTAssertTrue(filter.waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 3)
        let filterY = filter.frame.midY
        for _ in 0..<3 {
            select(filter, in: app)
            XCUIRemote.shared.press(.menu)
            for _ in 0..<4 { XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.25) }
            for _ in 0..<5 { XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.25) }
            XCTAssertEqual(filter.frame.midY, filterY, accuracy: 2)
            XCTAssertTrue(filter.isHittable)
        }
        select(filter, in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shows")).firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Filters after repeated scroll returns"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testAddonsInlineInstallLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--addons-ui-test"]
        app.launch()
        let field = app.textFields["addons.manifest"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        let install = app.buttons["addons.install"]
        XCTAssertTrue(install.exists)
        XCTAssertEqual(field.frame.midY, install.frame.midY, accuracy: 3)
        XCTAssertGreaterThan(install.frame.minX, field.frame.maxX)
        XCTAssertFalse(app.staticTexts["Install from manifest URL"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Add-ons inline install"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testSettingsCategorySelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--settings-ui-test"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["settings.pane.playback"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["settingsPaneTitle"].exists)
        select(app.cells.containing(.button, identifier: "settings.category.appearance").firstMatch, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.pane.appearance"].waitForExistence(timeout: 5))
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
