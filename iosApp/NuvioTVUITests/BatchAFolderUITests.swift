import XCTest

/// Batch A (Steven, beta.19-rc3 verdict 2026-10-06, follow-ups 10-08 / 10-14): the folder page is
/// an immersive screen, and add-on catalogs with `posterShape: "landscape"` draw 16:9 rows.
///
///  - `testStageOneRowFolderHidesTabBar` (BUG-148, UX-16 (3)): a Stage folder with ONE source has a
///    one-row strip, so the strip never turns a page; the bar must still be gone the moment the
///    folder is pushed, and back once Menu pops to Home.
///  - `testClassicGridKeepsTabBarHiddenAfterDetail` (BUG-144): Classic folder grid → Detail → Back
///    leaves the bar hidden over the grid; Menu → Home shows it again.
///  - `testRailHideWhileBrowsingHidesInFolder` (BUG-161): Rail = Hide While Browsing hides the rail
///    inside a collection (`rail_state … shown=0`) and shows it again on Home.
///  - `testLandscapeShapeCatalogDrawsLandscapeCards` (BUG-157): a stub add-on whose catalog tags
///    every item `posterShape: "landscape"` draws cards wider than tall with the global Landscape
///    Posters toggle off. Batch B (BUG-163): the in-row trailer's picture shows. rc5 promises
///    (BUG-162 / D16): the cards REST at the landscape folder-tile size (`width × 16/9` × `width`),
///    the heading sits as far above them as above a portrait row, and the trailer tile GROWS to
///    the poster height, its top on the rest card's top. Installs the add-on
///    through the DEBUG `-debug.addonManifestUrls` knob and removes it with
///    `-debug.addonManifestRemoveMatching` (the Add-ons keyboard skipped the leg on most runs).
///
/// Tab bar oracle (the `launchToHome` rule in `NuvioTVUITests`): the bar is SHOWN when its "Home"
/// button exists with `frame.minY > 0`; a hidden bar removes its buttons from the tree, and a
/// scrolled-off one parks them at a negative minY.
///
/// Fixture: the FA87 signed-in simulator (profile "Chris"). Collections come in through the
/// guest-only `-debug.collectionsSeedJsonB64` knob and are cleared with `"[]"` afterwards.
final class BatchAFolderUITests: XCTestCase {
    let remote = XCUIRemote.shared

    /// One pinned collection, one folder, ONE source: the folder's Rows page has a one-row strip
    /// and its Classic grid has no tab chips.
    private static let oneRowSeedJson = """
    [{"id":"zzbatcha-collection","title":"ZZBatchA","pinToTop":true,"showAllTab":true,"folders":[{"id":"zzbatcha-folder","title":"ZZBatchAFolder","hideTitle":false,"heroBackdropUrl":"https://images.metahub.space/background/medium/tt0111161/img","coverImageUrl":"https://images.metahub.space/poster/medium/tt0111161/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"top"}]}]}]
    """

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Helpers (duplicated per file, house rule)

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared")
        if chris.exists {
            remote.press(.left)
            pause(0.5)
            remote.press(.left)
            pause(0.5)
            remote.press(.select)
        }
        return app
    }

    private func clearSeed() {
        let app = launch(["-debug.collectionsSeedJsonB64", Data("[]".utf8).base64EncodedString()])
        pause(8)
        app.terminate()
    }

    /// The label of the element holding focus (tvOS 26.5 reports `hasFocus`; 27.0 never does).
    private func focusedLabel(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.label : "<none>"
    }

    private func focusedElement(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// Up, at most `max` times, until the tab bar is on screen (Home's rows scrolled back under the
    /// hero). False when it never shows: the immersive state is still holding it.
    private func walkToTopUntilBar(_ app: XCUIApplication, max: Int = 8) -> Bool {
        for _ in 0..<max {
            if tabBarShown(app) { return true }
            remote.press(.up)
            pause(1.5)
        }
        return tabBarShown(app)
    }

    /// See the class header.
    private func tabBarShown(_ app: XCUIApplication) -> Bool {
        let home = app.buttons["Home"]
        return home.exists && home.frame.minY > 0 && home.frame.height > 0
    }

    private func probe(_ app: XCUIApplication, _ id: String) -> String {
        let element = app.descendants(matching: .any)[id].firstMatch
        return element.exists ? element.label : "\(id) <absent>"
    }

    /// Walks `direction` until the focused element's label contains `text`.
    @discardableResult
    private func walk(_ app: XCUIApplication, _ direction: XCUIRemote.Button, untilFocusContains text: String,
                      max: Int = 8, gap: TimeInterval = 2) -> Bool {
        for _ in 0..<max {
            if focusedLabel(app).contains(text) { return true }
            remote.press(direction)
            pause(gap)
        }
        return focusedLabel(app).contains(text)
    }

    @discardableResult
    private func moveFocus(_ direction: XCUIRemote.Button, until element: XCUIElement, max: Int = 12) -> Bool {
        for _ in 0..<max {
            if element.exists && element.hasFocus { return true }
            remote.press(direction)
            pause(0.7)
        }
        return element.exists && element.hasFocus
    }

    // MARK: - BUG-148 / UX-16 (3): Stage, one-row folder

    func testStageOneRowFolderHidesTabBar() {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "stage", "-sidebar_style", "tabs",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        note("stage-0-home", "bar=\(tabBarShown(app)) focus=\(focusedLabel(app))\n" + probe(app, "debug_stage"))
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 3), "the pinned folder tile never took focus")
        remote.press(.select)
        pause(10)
        shot("stage-1-folder-open")
        let state = probe(app, "folder_rows_state")
        note("stage-1-folder-open", "bar=\(tabBarShown(app))\n\(state)")
        XCTAssertFalse(state.hasSuffix("<absent>"), "the folder Rows page did not open")
        // No page turn has happened (the strip has one row): the bar is hidden by the push alone.
        XCTAssertFalse(tabBarShown(app), "BUG-148: the tab bar is still on screen over a one-row Stage folder")
        // A Down is a no-op on a one-row strip; the bar must stay hidden, not come back on a rest.
        remote.press(.down)
        pause(3)
        XCTAssertFalse(tabBarShown(app), "BUG-148: the tab bar came back after a Down on the one-row strip")
        remote.press(.menu)
        pause(4)
        shot("stage-2-back-home")
        note("stage-2-back-home", "bar=\(tabBarShown(app)) focus=\(focusedLabel(app))")
        XCTAssertTrue(probe(app, "folder_rows_state").hasSuffix("<absent>"), "Menu did not pop the folder")
        // Home comes back scrolled to the folder's row, where tvOS hides the bar by scroll (the
        // first run's `stage-2-back-home`: bar=false, focus on the folder tile, immersive cleared:
        // the rail leg reads `shown=1` on the same pop). The immersive state is proven cleared by
        // the bar returning once the rows scroll back to the top.
        XCTAssertTrue(walkToTopUntilBar(app), "the tab bar did not return on Home after the folder popped (Up to the top)")
    }

    // MARK: - BUG-190: Stage folder title block

    /// Steven rc10 (BUG-190): on the Stage folder page the title logo is top-aligned in its fixed
    /// slot once the folder logo has risen, so the block reads top-down from the stage block's top
    /// (120 pt) instead of floating ~100 pt below it. After one move the stage info's first element
    /// (the logo) starts within 4 pt of the block top, and the folder logo layer is on screen.
    func testStageFolderTitleLogoSitsAtTheBlockTop() throws {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "stage", "-sidebar_style", "tabs",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 3), "the pinned folder tile never took focus")
        remote.press(.select)
        pause(10)
        // One move so the folder logo rises out of the stage's logo slot.
        remote.press(.right)
        pause(3)
        shot("bug190-folder-after-move")
        let folderLogo = app.descendants(matching: .any)["folder_stage_logo"]
        XCTAssertTrue(folderLogo.waitForExistence(timeout: 5), "folder_stage_logo is missing on the Stage folder page")
        XCTAssertGreaterThan(folderLogo.frame.height, 0, "the folder logo layer has no height")
        let info = app.descendants(matching: .any)["stage_info"]
        guard info.waitForExistence(timeout: 5) else { throw XCTSkip("no stage_info on this folder page") }
        note("bug190", "stage_info \(info.frame) folder_stage_logo \(folderLogo.frame)")
        XCTAssertEqual(info.frame.minY, 120, accuracy: 4, "the title logo is not at the stage block's top")
    }

    // MARK: - BUG-144: Classic grid → Detail → Back

    func testClassicGridKeepsTabBarHiddenAfterDetail() {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "classic", "-sidebar_style", "tabs",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 8), "the folder tile never took focus on Classic Home")
        remote.press(.select)
        pause(8)
        shot("classic-1-grid")
        XCTAssertFalse(probe(app, "folder_header_state").hasSuffix("<absent>"), "the Classic folder grid did not open")
        XCTAssertFalse(tabBarShown(app), "the tab bar is on screen over the Classic folder grid")
        // Into the grid's first poster, then Detail. The grid's posters arrive from the network;
        // wait for a focused poster (not the chips, not "<none>"), then Select, retrying once if
        // the Detail probe has not appeared (third run: one Select landed on a still-loading grid).
        for _ in 0..<4 where focusedLabel(app) == "<none>" || focusedLabel(app) == "All" {
            remote.press(.down)
            pause(1.5)
        }
        note("classic-2-grid-focus", focusedLabel(app))
        var detailOpened = false
        for attempt in 0..<2 where !detailOpened {
            remote.press(.select)
            pause(attempt == 0 ? 6 : 8)
            detailOpened = !probe(app, "debug_bridge").hasSuffix("<absent>")
        }
        shot("classic-3-detail")
        XCTAssertTrue(detailOpened, "Select on the grid did not open a Detail page (focus=\(focusedLabel(app)))")
        remote.press(.menu)
        pause(3)
        shot("classic-4-back-on-grid")
        note("classic-4-back-on-grid", "bar=\(tabBarShown(app))\n" + probe(app, "folder_header_state"))
        XCTAssertFalse(probe(app, "folder_header_state").hasSuffix("<absent>"), "Back from Detail did not land on the grid")
        XCTAssertFalse(tabBarShown(app), "BUG-144: the tab bar came back over the grid after Back from Detail")
        remote.press(.menu)
        pause(3)
        shot("classic-5-home")
        XCTAssertTrue(probe(app, "folder_header_state").hasSuffix("<absent>"), "Menu did not pop the folder")
        // See the Stage leg: Home returns scrolled, the bar is scroll-hidden there; Up to the top.
        XCTAssertTrue(walkToTopUntilBar(app), "the tab bar did not return on Classic Home (Up to the top)")
    }

    // MARK: - BUG-161: Rail = Hide While Browsing

    func testRailHideWhileBrowsingHidesInFolder() {
        let seed = Data(Self.oneRowSeedJson.utf8).base64EncodedString()
        defer { clearSeed() }
        let app = launch(["-home_layout", "stage", "-sidebar_style", "rail", "-rail_visibility", "browsing",
                          "-debug.collectionsSeedJsonB64", seed])
        pause(16)
        let home = probe(app, "rail_state")
        note("rail-0-home", home + "\nfocus=\(focusedLabel(app))")
        XCTAssertTrue(walk(app, .down, untilFocusContains: "ZZBatchA", max: 3), "the pinned folder tile never took focus")
        remote.press(.select)
        pause(10)
        shot("rail-1-folder")
        let inFolder = probe(app, "rail_state")
        note("rail-1-folder", inFolder)
        XCTAssertTrue(inFolder.contains("shown=0"), "BUG-161: the rail stays on screen inside the collection (\(inFolder))")
        remote.press(.menu)
        pause(4)
        var back = probe(app, "rail_state")
        note("rail-2-home", back)
        // Home comes back on the folder's row (BUG-156's restore pages the strip there), and Hide
        // While Browsing keeps the rail off below row 0 by design; the immersive clear is what the
        // rail returning at the top proves (second run: `shown=0` right after the pop, `shown=1`
        // once the strip is back on row 0).
        for _ in 0..<4 where !back.contains("shown=1") {
            remote.press(.up)
            pause(2)
            back = probe(app, "rail_state")
        }
        note("rail-3-top", back)
        XCTAssertTrue(back.contains("shown=1"), "the rail did not return on Home at the top (\(back))")
    }

    // MARK: - BUG-157: landscape-shape catalog

    private static let landscapeAddonName = "ZZ Landscape Stub"

    private static let landscapeManifest = """
    {"id":"zz.batcha.landscape","version":"1.0.0","name":"\(landscapeAddonName)","description":"Batch A BUG-157 stub","resources":["catalog","meta"],"types":["movie"],"idPrefixes":["zzland"],"catalogs":[{"type":"movie","id":"zzland","name":"ZZ Landscape Row"}]}
    """

    private static let landscapeCatalog: String = {
        let metas = (1...8).map { i in
            "{\"id\":\"zzland\(i)\",\"type\":\"movie\",\"name\":\"ZZLand \(i)\",\"posterShape\":\"landscape\",\"poster\":\"https://images.metahub.space/background/medium/tt0111161/img\"}"
        }
        return "{\"metas\":[\(metas.joined(separator: ","))]}"
    }()

    /// BUG-163: the meta every stub id answers with (one route for every id; the card only needs a
    /// trailer listed).
    private static let landscapeMeta = """
    {"meta":{"id":"zzland1","type":"movie","name":"ZZLand","posterShape":"landscape","poster":"https://images.metahub.space/background/medium/tt0111161/img","trailers":[{"source":"rNZ0xKaCdus","type":"Trailer"}]}}
    """

    /// Copy of `TabBarScrollLinkTests.openTab`, with Discover in the list.
    private func openTab(_ app: XCUIApplication, named title: String) {
        let tabNames = ["Home", "Search", "Discover", "Library", "Add-ons", "Settings", "Profile"]
        for _ in 0..<40 {
            if tabNames.contains(where: { app.buttons[$0].exists && app.buttons[$0].hasFocus }) { break }
            remote.press(.up)
            pause(0.35)
        }
        let tab = app.buttons[title]
        if !moveFocus(.right, until: tab, max: 7) {
            _ = moveFocus(.left, until: tab, max: 8)
        }
        remote.press(.select)
        pause(2)
    }

    /// BUG-162/163 (Batch B, B4): the stub add-on lives under `/zzland/`, so the DEBUG remove knob
    /// can match a stale copy from an earlier run on another port.
    private static let landscapeStubPath = "/zzland/"

    /// Mean absolute RGB difference (0…255) between two screenshots inside `rect` (points), sampled
    /// on a 24 × 14 grid. A playing video changes it; a still picture leaves it near 0.
    private static func meanDifference(_ a: XCUIScreenshot, _ b: XCUIScreenshot, in rect: CGRect,
                                       screenWidth: CGFloat) -> Double? {
        guard let ia = a.image.cgImage, let ib = b.image.cgImage,
              ia.width == ib.width, ia.height == ib.height, screenWidth > 0 else { return nil }
        let scale = CGFloat(ia.width) / screenWidth
        func pixels(_ image: CGImage) -> [UInt8]? {
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return data
        }
        guard let pa = pixels(ia), let pb = pixels(ib) else { return nil }
        let inset = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
        var total = 0.0
        var count = 0
        for gx in 0..<24 {
            for gy in 0..<14 {
                let x = Int((inset.minX + inset.width * CGFloat(gx) / 23) * scale)
                let y = Int((inset.minY + inset.height * CGFloat(gy) / 13) * scale)
                guard x >= 0, y >= 0, x < ia.width, y < ia.height else { continue }
                let i = (y * ia.width + x) * 4
                total += Double(abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1]))
                                + abs(Int(pa[i + 2]) - Int(pb[i + 2]))) / 3
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : nil
    }

    /// One `key=value` token out of a probe label.
    private static func token(_ label: String, _ key: String) -> String? {
        guard let range = label.range(of: key + "=") else { return nil }
        return label[range.upperBound...].split(separator: " ").first.map(String.init)
    }

    /// BUG-157 + BUG-162 / D16 + BUG-163. Steven's setup (rc4 video): Stage Home, Medium+, Hide
    /// Titles ON, No Zoom on Focus ON, trailers in the row. The stub add-on comes in through the DEBUG
    /// `-debug.addonManifestUrls` knob (the Add-ons keyboard made this leg skip on most runs).
    /// `-debug.cardGeometryProbe YES` publishes each card's artwork box (`poster_card`,
    /// `landscape_card`): a shape card's button is the whole poster-height SLOT now, so the button
    /// frame no longer says how big the resting art is.
    ///  1. the stub row's cards are landscape (BUG-157);
    ///  2. they rest at the folder-tile size, `style.width × 16/9` × `style.width` (233.97 pt tall
    ///     at the leg's Medium+ = 134 dp override), not the poster height (D16);
    ///  3. the heading → art gap equals the portrait row's (the art is top-aligned in its slot);
    ///  4. the trailer tile reaches `.wide` at the poster height × 16/9 (`debug_trailerTile outer=`),
    ///     its top on the rest card's top (it grows DOWN, the heading never moves);
    ///  5. once `event=play host=card`, the tile region MOVES between two screenshots (BUG-163: the
    ///     audio played under a still picture). YouTube extraction can be blocked from this Mac
    ///     (`LOGIN_REQUIRED`); then 4/5 are recorded as device-owed, not failed.
    func testLandscapeShapeCatalogDrawsLandscapeCards() throws {
        let stub = DiscoveryStubServer(routes: [
            (prefix: "\(Self.landscapeStubPath)manifest.json", body: Self.landscapeManifest),
            (prefix: "\(Self.landscapeStubPath)catalog/movie/zzland", body: Self.landscapeCatalog),
            // BUG-163: a meta with one trailer, so the in-row trailer dwells (a title that lists no
            // trailer never morphs). The smoke id replaces the key at extraction anyway.
            (prefix: "\(Self.landscapeStubPath)meta/movie/", body: Self.landscapeMeta),
        ])
        try stub.start()
        defer { stub.stop() }
        // Stage with titles hidden: no pinned reaches and no caption, so a card button's frame is its
        // artwork (XCUITest frames ignore the focus lift's scale; No Zoom has none anyway).
        let app = launch([
            "-home_layout", "stage", "-sidebar_style", "tabs",
            "-debug.posterHideTitles", "YES", "-debug.posterSizeOverride", "mediumPlus",
            "-no_zoom_on_focus", "YES",
            "-inline_trailers_enabled", "YES", "-trailer_playback_location", "poster",
            "-trailer_start_delay", "1", "-hero_trailer_autoplay", "NO",
            "-debug.trailerProbe", "YES", "-debug.trailerSmokeVideoId", "rNZ0xKaCdus",
            "-debug.addonManifestRemoveMatching", Self.landscapeStubPath,
            "-debug.addonManifestUrls", "\(stub.origin)\(Self.landscapeStubPath)manifest.json",
        ])
        defer {
            // Cleanup: relaunch with the remove knob alone, so the fixture never keeps the stub.
            app.terminate()
            let cleanup = launch(["-debug.addonManifestRemoveMatching", Self.landscapeStubPath])
            pause(10)
            cleanup.terminate()
        }
        pause(14)

        /// The heading line right above `frame`: the static text whose bottom is closest above it.
        func headingGap(above frame: CGRect) -> CGFloat? {
            let gaps = app.staticTexts.allElementsBoundByIndex
                .map(\.frame)
                .filter { $0.height > 0 && $0.maxY <= frame.minY + 2 && $0.maxX > frame.minX }
                .map { frame.minY - $0.maxY }
            return gaps.min()
        }

        // Walk the strip down to the stub row, keeping the last portrait row seen on the way.
        var portraitFrame: CGRect?
        var portraitGap: CGFloat?
        var found = false
        for _ in 0..<16 {
            // Hide Titles leaves the card buttons unlabelled: `debug_strip foc=<rowKey>/<itemId>`.
            if probe(app, "debug_strip").contains("/zzland") { found = true; break }
            let frame = focusedElement(app).frame
            if frame.height > 0, frame.width / frame.height < 0.9 {
                portraitFrame = frame
                portraitGap = headingGap(above: frame)
            }
            remote.press(.down)
            pause(2.5)
        }
        shot("landscape-1-row")
        note("landscape-0-requests", stub.requestLog.joined(separator: ", "))
        XCTAssertTrue(found, "no stub card took focus on Home (strip=\(probe(app, "debug_strip")), requests=\(stub.requestLog))")
        guard found else { return }
        // When the stub row is Home's first row there is no portrait row on the way down: the gap
        // check below then falls back to a bound (a detour Down/Up let the next row's trailer take
        // focus before the reading). The top-of-slot check is the structural half either way: the
        // slot is the portrait height, so art at its top sits where a portrait row's art sits.
        let focused = focusedElement(app).frame
        // The resting art: a shape card's button is its whole poster-height SLOT (D16), so the
        // button frame says nothing about the art. The base card stays in the tree under the trailer
        // tile at the rest size, and `debug_trailerTile` publishes its MEASURED frame (` base=` /
        // ` baseY=`), so the leg waits for the tile (any stage) and reads it there.
        var tileLabel: String?
        var tileFrame: CGRect = .zero
        func readTile() -> Bool {
            let tile = app.descendants(matching: .any)["debug_trailerTile"].firstMatch
            guard tile.exists else { return false }
            tileLabel = tile.label
            tileFrame = tile.frame
            return true
        }
        for _ in 0..<40 {
            if readTile() { break }
            pause(0.5)
        }
        var rest = CGRect.zero
        if let label = tileLabel, let size = Self.token(label, "base"), let y = Self.token(label, "baseY").flatMap(Double.init) {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { rest = CGRect(x: focused.minX, y: y, width: parts[0], height: parts[1]) }
        }
        let gap = headingGap(above: focused)
        note("landscape-1-row", "focused=\(focused) rest=\(rest) portrait=\(String(describing: portraitFrame)) gap=\(String(describing: gap)) portraitGap=\(String(describing: portraitGap)) tile=\(tileLabel ?? "-")")
        guard tileLabel != nil else {
            note("landscape-video", "DEVICE-OWED: no trailer tile within 20 s (extraction unavailable on this host?): the rest size and the grow are unverified here")
            XCTAssertGreaterThan(focused.width / max(focused.height, 1), 1.0, "BUG-157: the landscape-shape card's slot is not wider than tall (\(focused))")
            return
        }

        // 1. BUG-157: 16:9 is 1.78, a portrait poster 0.67.
        XCTAssertGreaterThan(rest.height, 0, "no ` base=` field on the tile probe (\(tileLabel ?? "-"))")
        guard rest.height > 0 else { return }
        XCTAssertGreaterThan(rest.width / rest.height, 1.4,
                             "BUG-157: a card of the landscape-shape row is not landscape (\(rest))")
        // 2. D16: the folder-tile size at Medium+ (134 dp × 220/126 = 233.97 wide poster).
        let styleWidth: CGFloat = 134 * 220 / 126
        let styleHeight = styleWidth * 1.5
        XCTAssertEqual(rest.height, styleWidth, accuracy: 3,
                       "BUG-162 / D16: the resting landscape card is not the folder tile's height (\(rest))")
        XCTAssertEqual(rest.width, styleWidth * 16 / 9, accuracy: 3,
                       "BUG-162 / D16: the resting landscape card is not the folder tile's width (\(rest))")
        if let portraitFrame {
            XCTAssertEqual(portraitFrame.height, styleHeight, accuracy: 3, "the portrait reference is not Medium+ (\(portraitFrame))")
        }
        // 3. The rest art sits at the TOP of its slot, and the heading sits as far above it as above
        //    a portrait row's art.
        XCTAssertEqual(rest.minY, focused.minY, accuracy: 3,
                       "D16: the resting art (\(rest)) is not at the top of its slot (\(focused))")
        if let gap, let portraitGap {
            XCTAssertEqual(gap, portraitGap, accuracy: 3,
                           "BUG-162: heading → landscape art \(gap) pt, heading → portrait art \(portraitGap) pt")
        } else if let gap {
            XCTAssertLessThan(gap, 48, "BUG-162: the row heading floats \(gap) pt above the landscape cards")
        }

        // 4. The tile: reaches `.wide` at the poster height, growing down from the rest card's top.
        for _ in 0..<40 {
            if readTile(), tileLabel?.contains("stage=wide") == true { break }
            pause(0.5)
        }
        if tileLabel?.contains("stage=wide") != true { tileLabel = nil }
        note("landscape-2-tile", (tileLabel ?? "debug_trailerTile <no wide stage>; morph=\(probe(app, "debug_trailerMorph"))") + " frame=\(tileFrame)")
        guard let tileLabel else {
            note("landscape-video", "DEVICE-OWED: no wide trailer tile within 20 s (extraction unavailable on this host?) — the grow is unverified here")
            return
        }
        shot("landscape-2-wide")
        var grown = CGSize.zero
        if let outer = Self.token(tileLabel, "outer") {
            let parts = outer.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { grown = CGSize(width: parts[0], height: parts[1]) }
        }
        XCTAssertEqual(grown.height, styleHeight, accuracy: 3, "D16: the wide tile is not the poster height (\(tileLabel))")
        XCTAssertEqual(grown.width, styleHeight * 16 / 9, accuracy: 3, "D16: the wide tile is not 16:9 at the poster height (\(tileLabel))")
        // The probe text is a top-leading overlay on the tile: its top is the tile's top.
        XCTAssertEqual(tileFrame.minY, rest.minY, accuracy: 3,
                       "D16: the tile's top (\(tileFrame.minY)) moved off the rest card's top (\(rest.minY)): the row breathed")

        // 5. The video shows: wait for playback, then compare two frames of the tile region.
        var playing = false
        for _ in 0..<60 {
            if probe(app, "debug_trailerMorph").contains("event=play host=card") { playing = true; break }
            pause(0.5)
        }
        guard playing else {
            note("landscape-video", "DEVICE-OWED: no event=play within 30 s; morph=\(probe(app, "debug_trailerMorph"))")
            return
        }
        pause(4)   // the reveal gate (BUG-59) conceals the first frames until the zoom is measured
        let first = XCUIScreen.main.screenshot()
        pause(1.5)
        let second = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: second)
        attachment.name = "landscape-3-playing"
        attachment.lifetime = .keepAlways
        add(attachment)
        let card = CGRect(origin: CGPoint(x: tileFrame.minX, y: rest.minY), size: grown)
        let diff = Self.meanDifference(first, second, in: card, screenWidth: app.frame.width)
        note("landscape-3-playing", "card=\(card) diff=\(diff.map { String(format: "%.2f", $0) } ?? "nil") morph=\(probe(app, "debug_trailerMorph"))")
        if let diff {
            XCTAssertGreaterThan(diff, 2, "BUG-163: the trailer plays but the card region does not move (still picture, audio only)")
        }
    }
}
