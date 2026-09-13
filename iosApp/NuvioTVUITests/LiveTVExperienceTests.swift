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
    @MainActor private func openSharedSettings(_ app: XCUIApplication, details: Bool = false) {
        let settings = app.buttons["player.settings"]
        // Use the physical remote sequence: tvOS can omit hasFocus for glass buttons inside
        // a full-screen cover, so an AX focus-search loop cannot reliably select them.
        if settings.exists {
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        }
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons["player.panel.tab.playback"].value as? String, "selected", "Settings starts on Playback")
        select(app.buttons[details ? "player.panel.tab.info" : "player.panel.tab.playback"], in: app)
        let tab = app.buttons[details ? "player.panel.tab.info" : "player.panel.tab.playback"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(tab.value as? String, "selected", app.debugDescription)
    }

    @MainActor private func verifyDrawer(_ app: XCUIApplication) {
        let audio = app.buttons["player.panel.tab.audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(audio.frame.minY, 350, "Player tabs must be in the bottom drawer")
        let tabOrigin = audio.frame.origin
        select(audio, in: app)
        XCTAssertEqual(audio.value as? String, "selected")
        select(app.buttons["player.panel.tab.subtitles"], in: app)
        XCTAssertEqual(app.buttons["player.panel.tab.subtitles"].value as? String, "selected")
        select(app.buttons["player.panel.tab.info"], in: app)
        XCTAssertEqual(app.buttons["player.panel.tab.info"].value as? String, "selected")
        XCTAssertEqual(audio.frame.minX, tabOrigin.x, accuracy: 1, "Panel width stays fixed across tabs")
        XCTAssertEqual(audio.frame.minY, tabOrigin.y, accuracy: 1, "Panel height stays fixed across tabs")
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
        openSharedSettings(app)
        verifyDrawer(app)
        select(app.buttons["Next channel"], in: app)
        Thread.sleep(forTimeInterval: 2)
        openSharedSettings(app)
        select(app.buttons["Channel guide"], in: app)
        XCTAssertTrue(app.buttons["Sources"].waitForExistence(timeout: 10))
    }

    @MainActor func testNativeMovieBottomDrawer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--native-player-ui-test"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["player.timeline"].waitForExistence(timeout: 60), app.debugDescription)
        Thread.sleep(forTimeInterval: 3)
        openSharedSettings(app)
        verifyDrawer(app)
        verifyMovieControls(app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["player.timeline"].exists)
    }

    @MainActor func testNativeNestedPlayerSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--nested-native-player-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Continue Watching"].waitForExistence(timeout: 20))
        select(app.buttons["Continue Watching"], in: app)
        XCTAssertTrue(app.buttons["First stream"].waitForExistence(timeout: 5))
        select(app.buttons["First stream"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["player.timeline"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 3)
        for details in [true, false] {
            openSharedSettings(app, details: details)
            verifyDrawer(app)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["player.timeline"].exists)
        }
    }

    @MainActor func testMPVDirectTrackControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--mpv-player-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["player.audio"].waitForExistence(timeout: 20))
        XCUIRemote.shared.press(.playPause)
        // Exercise the user-facing remote sequence. tvOS 27 can omit hasFocus on a glass
        // Button after modal dismissal; assert the resulting panel instead of that AX flag.
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["player.panel.tab.audio"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player.panel.tab.audio"].value as? String, "selected")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.audio"].waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["player.panel.tab.subtitles"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player.panel.tab.subtitles"].value as? String, "selected")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.subtitles"].waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: app.buttons["player.audio"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertTrue(app.otherElements["player.mpv"].exists, "First Back hides controls without exiting the film")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(app.buttons["player.settings"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback")).firstMatch.waitForExistence(timeout: 5))
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

    @MainActor func testFixedPanelDetailsScroll() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--player-panel-ui-test"]
        app.launch()
        let audio = app.buttons["player.panel.tab.audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 20))
        XCTAssertEqual(audio.value as? String, "selected")
        let origin = CGPoint(x: audio.frame.midX, y: audio.frame.midY)
        select(app.buttons["player.panel.tab.info"], in: app)
        XCTAssertEqual(audio.frame.midX, origin.x, accuracy: 1)
        XCTAssertEqual(audio.frame.midY, origin.y, accuracy: 1)
        let last = app.descendants(matching: .any)["player.details.row.Detail 20"]
        select(last, in: app)
        XCTAssertTrue(last.isHittable, "Details must scroll to the final diagnostic row")
        let first = app.descendants(matching: .any)["player.details.row.Detail 1"]
        select(first, in: app)
        XCTAssertTrue(first.isHittable, "Details must scroll back to the beginning")
        let header = app.descendants(matching: .any)["player.details.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        var reachedSynopsis = false
        for _ in 0..<8 {
            XCUIRemote.shared.press(.up)
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.identifier.hasPrefix("player.details.synopsis.") { reachedSynopsis = true }
            if header.hasFocus { break }
        }
        XCTAssertTrue(reachedSynopsis, "The complete synopsis must remain scrollable")
        XCTAssertTrue(header.hasFocus, "Up must restore the title, rather than skip from details to the tabs")
        XCTAssertTrue(header.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Fixed panel scrollable Details"; screenshot.lifetime = .keepAlways; add(screenshot)
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
        try verifySharedTransport(launchArgument: "--mpv-player-ui-test")
    }

    @MainActor func testNativeTransportAfterDrawer() throws {
        try verifySharedTransport(launchArgument: "--native-player-ui-test")
    }

    @MainActor private func verifySharedTransport(launchArgument: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [launchArgument]
        app.launch()
        let timeline = app.descendants(matching: .any)["player.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 20))
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND value != %@", "Playing, playback position", "0:00"), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 30), .completed, "Wait for decoded playback before testing transport")
        XCTAssertFalse(app.buttons["player.playPause"].exists, "Use native-style timeline/remote playback control without a duplicate Play/Pause button")
        let transportHeight = timeline.frame.maxY - app.buttons["player.settings"].frame.minY
        XCTAssertGreaterThan(transportHeight, 60, "The timeline belongs beneath the transport buttons")
        XCTAssertLessThan(transportHeight, 180, "Native-size actions and timeline should remain a compact bottom control area")
        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "Shared transport \(launchArgument)"; compact.lifetime = .keepAlways; add(compact)
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(timeline.label, "Paused, playback position", "The remote Play/Pause button must pause exactly once")
        select(timeline, in: app)
        XCTAssertEqual(timeline.label, "Playing, playback position", "Select on the timeline must resume")
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(timeline.label, "Paused, playback position")
        select(app.buttons["player.settings"], in: app)
        let playback = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Playback")).firstMatch
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        select(playback, in: app)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["player.panel.tab.playback"].waitForNonExistence(timeout: 5))
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(timeline.label, "Playing, playback position", "Play/Pause must work after closing Settings")
        let elapsed = app.descendants(matching: .any)["player.timeline"]
        let previous = elapsed.value as? String ?? ""
        let advances = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previous), object: elapsed)
        XCTAssertEqual(XCTWaiter.wait(for: [advances], timeout: 4), .completed, "Playback time must continue updating after the drawer closes")
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(timeline.label, "Paused, playback position")
        XCTAssertTrue(timeline.exists, "The visible timeline must be focusable for seeking")
        // Move focus without selecting: Select on the timeline intentionally toggles playback.
        for _ in 0..<3 where !timeline.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(timeline.hasFocus, app.debugDescription)
        let pausedAt = timeline.value as? String ?? ""
        Thread.sleep(forTimeInterval: 4.5)
        XCTAssertTrue(app.staticTexts["player.transport.title"].exists, "Pause keeps the title visible past the normal hide timeout")
        XCTAssertTrue(timeline.isHittable, "Pause keeps the timeline visible")
        XCTAssertEqual(timeline.value as? String, pausedAt, "The film must actually remain paused")
        let pauseShot = XCTAttachment(screenshot: app.screenshot())
        pauseShot.name = "Shared paused transport \(launchArgument)"; pauseShot.lifetime = .keepAlways; add(pauseShot)
        let beforeSeek = timeline.value as? String ?? ""
        XCUIRemote.shared.press(.right)
        let seeks = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", beforeSeek), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [seeks], timeout: 5), .completed, "Right on the timeline must change playback position")
        let forward = timeline.value as? String ?? ""
        XCUIRemote.shared.press(.left)
        let seeksBack = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", forward), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [seeksBack], timeout: 5), .completed)
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(timeline.label, "Playing, playback position", "Select on the timeline must resume exactly once")
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
            let filterOptions = ["Browse: Movies", "Genre: All genres", "Catalog: All catalogs", "Sort: Recommended"]
            let expectedOptions = ["Shows", "Action", "All catalogs", "A–Z"]
            var returnedFilter: Int?
            for _ in 0..<8 {
                XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.35)
                let current = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
                // Native Menu places focus on its hosting view, not the AX button itself.
                let center = CGPoint(x: current.frame.midX, y: current.frame.midY)
                if !current.frame.isEmpty {
                    returnedFilter = filterOptions.firstIndex { app.buttons[$0].frame.contains(center) }
                    if returnedFilter != nil { break }
                }
            }
            XCTAssertNotNil(returnedFilter, "Up must focus the filter bar before reaching the hero or sidebar")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", expectedOptions[returnedFilter ?? 0])).firstMatch.waitForExistence(timeout: 3), "Select after scrolling up must open the filter")
            XCUIRemote.shared.press(.menu)
            XCTAssertEqual(filter.frame.midY, filterY, accuracy: 2)
            XCTAssertTrue(filter.isHittable)
        }
        select(filter, in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Shows")).firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Filters after repeated scroll returns"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testWelcomeAccountRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--welcome-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Sign In with Your Phone"].waitForExistence(timeout: 15))
        select(app.buttons["Sign In with Email"], in: app)
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        XCTAssertFalse(app.buttons["Sign In"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native email sign in"; screenshot.lifetime = .keepAlways; add(screenshot)
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

    @MainActor func testAddonsLivesInSettingsAndBackReturns() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--settings-ui-test"]
        app.launch()
        let category = app.buttons["settings.category.contentSources"]
        XCTAssertTrue(category.waitForExistence(timeout: 20))
        select(app.cells.containing(.button, identifier: "settings.category.contentSources").firstMatch, in: app)
        select(app.cells.containing(.button, identifier: "settings.addons").firstMatch, in: app)
        XCTAssertTrue(app.textFields["addons.manifest"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(category.waitForExistence(timeout: 10), "Back from Add-ons must return to Settings")
        XCTAssertTrue(app.cells.containing(.button, identifier: "settings.addons").firstMatch.isHittable)
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
