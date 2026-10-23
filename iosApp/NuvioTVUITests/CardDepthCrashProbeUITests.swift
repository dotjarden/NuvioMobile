import XCTest

/// BUG-221 regression leg (2026-10-23): Home must survive its first publishes with Card Depth ON.
///
/// The W3-13 raster-cache rendering (a `GeometryReader` overlay per card) trapped in SwiftUI's
/// `DynamicContainerInfo.tryRemovingItem` about 1.5 s after the profile pick, under
/// `_AspectRatioLayout` inside a `LazyHStack` row, with no input: the folder legs (test106-108,
/// which launch exactly like this) crashed 8 / 8 on FA87 with Card Depth left on by an earlier leg.
/// This leg forces Card Depth on through `-debug.cardDepthOn YES` (master + every surface, DEBUG,
/// never written or synced), launches Stage and Classic Home `launches` times each with the folder
/// seed the folder legs use, and watches the app for 20 s after the pick: any exit fails the leg.
///
/// `TEST_RUNNER_NUVIO_DEPTH_PROBE_LAUNCHES=<n>` raises the per-layout launch count (default 2).
/// Helpers are a trimmed copy of `NuvioTVUITests`' (private there; this harness accepts duplication
/// over shared helpers, see `HeroOffLaunchTests`).
final class CardDepthCrashProbeUITests: XCTestCase {

    private static let folderSeedJson = """
    [{"id":"zzfolderrows-collection","title":"ZZFolderRows","pinToTop":true,"showAllTab":true,"folders":[{"id":"zzfolderrows-folder","title":"ZZFolderRowsFolder","hideTitle":false,"heroBackdropUrl":"https://images.metahub.space/background/medium/tt0111161/img","coverImageUrl":"https://images.metahub.space/poster/medium/tt0111161/img","sources":[{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"top"},{"provider":"addon","addonId":"com.linvo.cinemeta","type":"series","catalogId":"top"},{"provider":"addon","addonId":"com.linvo.cinemeta","type":"movie","catalogId":"imdbRating"},{"provider":"addon","addonId":"zz.missing.addon","type":"movie","catalogId":"zzmissing"}]}]}]
    """

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private var launches: Int {
        Int(ProcessInfo.processInfo.environment["NUVIO_DEPTH_PROBE_LAUNCHES"] ?? "") ?? 2
    }

    private func launch(layout: String, seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        let b64 = Data(seed.utf8).base64EncodedString()
        app.launchArguments += ["-home_layout", layout,
                                "-debug.collectionsSeedJsonB64", b64,
                                "-debug.homeScrollProbe", "YES", "-inline_trailers_enabled", "NO",
                                "-home_upcoming_row_enabled", "NO",
                                "-debug.trailerProbe", "YES", "-debug.trailerForceNoTrailer", "YES",
                                "-debug.cardDepthOn", "YES"]
        app.launch()
        return app
    }

    /// Picks "Chris" (focus-verified) and watches the app for `seconds`. Returns the second the app
    /// left the foreground, or nil when it survived.
    private func survives(_ app: XCUIApplication, seconds: TimeInterval) -> TimeInterval? {
        guard DetailEntryRoute.selectChrisTile(self, app, timeout: 90) == true else {
            XCTFail("the profile pick never happened")
            return nil
        }
        // `app.state` can keep reading `.runningForeground` after a trap on the simulator, so the
        // watch also takes an accessibility snapshot each second: a dead app has none to give.
        // (XCTest records the crash as a failure of its own either way.)
        func alive() -> Bool { app.state == .runningForeground && (try? app.snapshot()) != nil }
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            if !alive() { return Date().timeIntervalSince(start) }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return alive() ? nil : seconds
    }

    func testHomeSurvivesFirstPublishesWithCardDepthOn() throws {
        defer {
            let restored = launch(layout: "classic", seed: "[]")
            _ = survives(restored, seconds: 8)
        }
        var exits: [String] = []
        for layout in ["stage", "classic"] {
            for run in 1...launches {
                let app = launch(layout: layout, seed: Self.folderSeedJson)
                let exitAt = survives(app, seconds: 20)
                let line = "\(layout) #\(run): " + (exitAt.map { String(format: "EXITED after %.1f s", $0) } ?? "alive 20 s")
                add(XCTAttachment(string: line))
                print("[CardDepthCrashProbe] \(line)")
                if exitAt != nil { exits.append(line) }
                app.terminate()
            }
        }
        XCTAssertTrue(exits.isEmpty, "Home left the foreground with Card Depth on (BUG-221): \(exits)")
    }

    /// Measurement walk (opt-in, `TEST_RUNNER_NUVIO_DEPTH_WALK=1`): Classic Home with Card Depth on,
    /// then the R1 walk's shape, 20 Down and 20 Up at 0.6 s, for a profiler attached from outside
    /// (`[CardDepthWalk] start` / `end` mark the window in the log). The simulator has no
    /// Animation Hitches instrument; this leg exists for a Time Profiler A/B of the rendering.
    func testDepthWalkClassicHome() throws {
        guard ProcessInfo.processInfo.environment["NUVIO_DEPTH_WALK"] == "1" else {
            throw XCTSkip("measurement walk: set TEST_RUNNER_NUVIO_DEPTH_WALK=1 to run it")
        }
        let app = launch(layout: "classic", seed: "[]")
        XCTAssertNil(survives(app, seconds: 12), "Home must be up before the walk")
        let remote = XCUIRemote.shared
        print("[CardDepthWalk] start \(Date().timeIntervalSince1970)")
        for button in [XCUIRemote.Button.down, .up] {
            for _ in 0..<20 {
                remote.press(button)
                Thread.sleep(forTimeInterval: 0.6)
            }
        }
        print("[CardDepthWalk] end \(Date().timeIntervalSince1970)")
        XCTAssertTrue(app.state == .runningForeground)
    }
}
