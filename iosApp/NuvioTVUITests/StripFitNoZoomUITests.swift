import XCTest

/// BUG-191 (Steven rc9, No Zoom): on Stage Home a collection row's captions faded into the next
/// page's 24 pt top feather. With No Zoom the focus lift is 0, so a Short Rows Fit page used to be
/// exactly the measured row, and a collection row (12 pt of bottom padding against a catalog row's
/// 24) ended inside the feather. The fix (`StripGeometry.fitPageHeight`) adds the feather's 24 pt
/// band under every row when the lift is 0.
///
/// Oracle: the DEBUG `debug_strip_fit` readout, `key=<rowKey> m=<measured> h=<page> | …` for every
/// measured row in strip order (`-` before any measurement or with Short Rows Fit off). The leg
/// asserts h ≥ m + 24 (or h = P, the cap) for the seeded collection row.
///
/// Fixture: FA87, guest "Chris" profile with Cinemeta. Two unpinned collections come in through the
/// guest-only `-debug.collectionsSeedJsonB64` knob (BUG-38's seeding recipe). New collections sort
/// to the back of the Home order in definition order, so ZZFitA is the SECOND-TO-LAST row (ZZFitB
/// follows it) and its page has a page after it, which is the shape Steven reported. The seed is
/// cleared with `"[]"` afterwards. The A/B (`-debug.stripFitRows NO`) shows the fixed pages.
///
/// Helpers are this file's own (the harness's duplication rule).
final class StripFitNoZoomUITests: XCTestCase {

    let remote = XCUIRemote.shared

    private static let seedJson = """
    [{"id":"zzfit-a","title":"ZZFitA","pinToTop":false,"showAllTab":true,"folders":[{"id":"zzfit-a-folder","title":"ZZFitAFolder","hideTitle":false,"coverImageUrl":"https://images.metahub.space/poster/medium/tt0111161/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"top"}]}]},{"id":"zzfit-b","title":"ZZFitB","pinToTop":false,"showAllTab":true,"folders":[{"id":"zzfit-b-folder","title":"ZZFitBFolder","hideTitle":false,"coverImageUrl":"https://images.metahub.space/poster/medium/tt0068646/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"series","catalogId":"top"}]}]}]
    """

    /// `StageStripHome.rowKeys`: the strip keys a collection row by its bare `collection.id`.
    private static let collectionRowKey = "zzfit-a"

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
        print("[StripFitNoZoomUITests] \(name): \(text)")
    }

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the FA87 fixture set up?")
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

    private func probe(_ app: XCUIApplication, _ id: String) -> String {
        let element = app.descendants(matching: .any)[id].firstMatch
        return element.exists ? element.label : "\(id) <absent>"
    }

    /// `key=value` out of a readout line, matched on the exact key.
    private static func token(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0] == Substring(key) else { continue }
            return String(pair[1])
        }
        return nil
    }

    /// One row's `(m, h)` out of `debug_strip_fit`, nil when that row has no measurement yet.
    private static func fit(_ line: String, rowKey: String) -> (measured: Double, page: Double)? {
        let body = line.hasPrefix("debug_strip_fit ") ? String(line.dropFirst("debug_strip_fit ".count)) : line
        for entry in body.components(separatedBy: " | ") where token(entry, "key") == rowKey {
            guard let m = token(entry, "m").flatMap(Double.init),
                  let h = token(entry, "h").flatMap(Double.init) else { return nil }
            return (m, h)
        }
        return nil
    }

    /// Down until the strip's row stops changing (the end of Home), at most `max` presses.
    private func walkToEnd(_ app: XCUIApplication, max: Int = 16) {
        var last = Self.token(probe(app, "debug_strip"), "row")
        var still = 0
        for _ in 0..<max {
            remote.press(.down)
            pause(1.8)
            let row = Self.token(probe(app, "debug_strip"), "row")
            if row == last { still += 1 } else { still = 0 }
            last = row
            if still >= 2 { return }
        }
    }

    private static func arguments(fitRows: Bool, seed: String) -> [String] {
        ["-home_layout", "stage", "-sidebar_style", "tabs", "-home_upcoming_row_enabled", "NO",
         "-inline_trailers_enabled", "NO", "-no_zoom_on_focus", "YES",
         "-debug.homeScrollProbe", "YES", "-debug.stripFitRows", fitRows ? "YES" : "NO",
         "-debug.collectionsSeedJsonB64", seed]
    }

    // MARK: - BUG-191

    func testNoZoomCollectionRowPageClearsTheFeather() {
        let seed = Data(Self.seedJson.utf8).base64EncodedString()
        defer { clearSeed() }

        // A: Short Rows Fit on (the shipping default), No Zoom.
        let app = launch(Self.arguments(fitRows: true, seed: seed))
        pause(16)
        let page = Self.token(probe(app, "debug_stage"), "P").flatMap(Double.init) ?? 0
        walkToEnd(app)
        pause(2)
        let fitLine = probe(app, "debug_strip_fit")
        note("A_fit", "P=\(page)\n\(fitLine)\n\(probe(app, "debug_strip"))")
        shot("A_end_of_home")
        // Up once: the collection row (second to last) at rest, its page bottom over the last row's.
        remote.press(.up)
        pause(2)
        shot("A_collection_row_at_rest")
        if let row = Self.fit(fitLine, rowKey: Self.collectionRowKey) {
            XCTAssertGreaterThan(row.measured, 0, "unmeasured collection row: \(fitLine)")
            let capped = page > 0 && abs(row.page - page) < 0.01
            XCTAssertTrue(row.page >= row.measured + 24 - 0.01 || capped,
                          "BUG-191: the No Zoom fit page must clear the 24 pt feather (h ≥ m + 24, or h = P \(page)): \(fitLine)")
        } else {
            XCTFail("the seeded collection row \(Self.collectionRowKey) never reported a fit page: \(fitLine)")
        }
        app.terminate()

        // B: Short Rows Fit off. Pages are the fixed P; the readout stays `-`.
        let appB = launch(Self.arguments(fitRows: false, seed: seed))
        pause(16)
        walkToEnd(appB)
        pause(2)
        let fitLineB = probe(appB, "debug_strip_fit")
        note("B_fit", "\(fitLineB)\n\(probe(appB, "debug_stage"))")
        shot("B_end_of_home")
        XCTAssertEqual(fitLineB, "debug_strip_fit -", "Short Rows Fit off measures nothing: \(fitLineB)")
        appB.terminate()
    }
}
