import XCTest
import SharedCore
@testable import NuvioTV

/// Orivio batch, item 5 (app side): the per-install callback scheme an external player returns on,
/// and the guarantee that such a callback never becomes a Top Shelf deep-link cover. All pure —
/// the scheme pick and `isCallback` take their inputs as parameters, so nothing here reads the
/// host bundle's plist.
final class DeepLinkTests: XCTestCase {
    private let installScheme = "com.youngchris29.NuvioTV"

    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            XCTFail("not a URL: \(string)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }

    // MARK: - AppCallbackScheme.pick

    func testPickReturnsTheSecondSchemeWhenTheBundleIdentifierIsRegistered() {
        let types: [[String: Any]] = [[
            "CFBundleURLName": "com.nuvio.media.NuvioTV.deeplink",
            "CFBundleURLSchemes": ["nuviotv", installScheme],
        ]]
        XCTAssertEqual(AppCallbackScheme.pick(from: types), installScheme)
    }

    func testPickFindsTheSchemeInALaterURLTypeEntry() {
        let types: [[String: Any]] = [
            ["CFBundleURLSchemes": ["nuviotv"]],
            ["CFBundleURLSchemes": [installScheme]],
        ]
        XCTAssertEqual(AppCallbackScheme.pick(from: types), installScheme)
    }

    func testPickSkipsTheTopShelfSchemeCaseInsensitively() {
        let types: [[String: Any]] = [["CFBundleURLSchemes": ["NuvioTV", installScheme]]]
        XCTAssertEqual(AppCallbackScheme.pick(from: types), installScheme)
    }

    func testPickFallsBackToTheTopShelfSchemeWhenNothingElseIsRegistered() {
        XCTAssertEqual(AppCallbackScheme.pick(from: []), "nuviotv")
        XCTAssertEqual(AppCallbackScheme.pick(from: [["CFBundleURLSchemes": ["nuviotv"]]]), "nuviotv")
        XCTAssertEqual(AppCallbackScheme.pick(from: [["CFBundleURLName": "no schemes key"]]), "nuviotv")
    }

    // MARK: - ExternalPlaybackReturnRouter.isCallback

    func testIsCallbackAcceptsTheInstallSchemeOnTheExternalPlayerHost() {
        let callback = url("\(installScheme)://external-player/infuse/SESSION/success?lastPlayedUrl=https%3A%2F%2Fx&position=42")
        XCTAssertTrue(ExternalPlaybackReturnRouter.isCallback(callback, callbackScheme: installScheme))
        let failure = url("\(installScheme)://external-player/infuse/SESSION/error")
        XCTAssertTrue(ExternalPlaybackReturnRouter.isCallback(failure, callbackScheme: installScheme))
    }

    func testIsCallbackIsCaseInsensitiveOnTheScheme() {
        let upper = url("COM.YOUNGCHRIS29.NUVIOTV://external-player/infuse/SESSION/success?position=1")
        XCTAssertTrue(ExternalPlaybackReturnRouter.isCallback(upper, callbackScheme: installScheme))
        let upperTopShelf = url("NuvioTV://external-player/infuse/SESSION/success?position=1")
        XCTAssertTrue(ExternalPlaybackReturnRouter.isCallback(upperTopShelf, callbackScheme: installScheme))
    }

    func testIsCallbackAlsoSwallowsACallbackOnTheSharedTopShelfScheme() {
        let callback = url("nuviotv://external-player/infuse/SESSION/success?position=1")
        XCTAssertTrue(ExternalPlaybackReturnRouter.isCallback(callback, callbackScheme: installScheme))
    }

    func testIsCallbackRejectsOtherHostsAndSchemes() {
        XCTAssertFalse(ExternalPlaybackReturnRouter.isCallback(url("nuviotv://resume?videoId=tt1&type=movie"), callbackScheme: installScheme))
        XCTAssertFalse(ExternalPlaybackReturnRouter.isCallback(url("nuviotv://title?id=tt1&type=movie"), callbackScheme: installScheme))
        XCTAssertFalse(ExternalPlaybackReturnRouter.isCallback(url("\(installScheme)://title?id=tt1"), callbackScheme: installScheme))
        XCTAssertFalse(ExternalPlaybackReturnRouter.isCallback(url("infuse://external-player/infuse/SESSION/success"), callbackScheme: installScheme))
        XCTAssertFalse(ExternalPlaybackReturnRouter.isCallback(url("https://external-player/infuse/SESSION/success"), callbackScheme: installScheme))
    }

    func testIsCallbackFollowsTheCallbackSchemeItIsGiven() {
        let callback = url("\(installScheme)://external-player/infuse/SESSION/success?position=1")
        XCTAssertFalse(ExternalPlaybackReturnRouter.isCallback(callback, callbackScheme: "com.nuvio.media.NuvioTV"))
    }

    // MARK: - ExternalPlaybackReturnRouter.outcome

    func testOutcomeReadsTheLastPathSegment() {
        XCTAssertEqual(
            ExternalPlaybackReturnRouter.outcome(of: url("\(installScheme)://external-player/infuse/SESSION/success?position=3")),
            .success
        )
        XCTAssertEqual(
            ExternalPlaybackReturnRouter.outcome(of: url("\(installScheme)://external-player/infuse/SESSION/error")),
            .error
        )
        XCTAssertNil(ExternalPlaybackReturnRouter.outcome(of: url("\(installScheme)://external-player/infuse/SESSION/other")))
        XCTAssertNil(ExternalPlaybackReturnRouter.outcome(of: url("\(installScheme)://external-player/success")))
    }

    // MARK: - FEAT-56 (SenPlayer): return session + probe redaction

    func testInfuseSenPlayerAndNativePlayerReportTheirStopPositionBack() {
        // All three get `ExternalPlaybackReturn` sessions and x-success / x-error callback URLs from
        // the picker (Native Player since FEAT-78); every other player gets none (`openExternally`).
        XCTAssertEqual(StreamPickerView.returnReportingPlayerIds, ["infuse", "senplayer", "nativeplayer"])
    }

    private func redactedValue(_ name: String, in printed: String) -> Bool {
        printed.contains("\(name)=%3Credacted%3E") || printed.contains("\(name)=<redacted>")
    }

    func testProbeRedactsTheLastPlayedUrlAndKeepsThePosition() {
        let callback = url("\(installScheme)://external-player/senplayer/SESSION/success?lastPlayedUrl=https%3A%2F%2Fcdn.example.com%2Frealdebrid%2FSECRET%2Ffile.mkv&position=42.5")
        let printed = ExternalPlaybackReturnRouter.redactedForProbe(callback)
        XCTAssertFalse(printed.contains("SECRET"))
        XCTAssertFalse(printed.contains("cdn.example.com"))
        XCTAssertTrue(redactedValue("lastPlayedUrl", in: printed), printed)
        XCTAssertTrue(printed.contains("position=42.5"), "the parameter the device test is looking for stays readable")
        XCTAssertTrue(printed.hasPrefix("\(installScheme)://external-player/senplayer/SESSION/success?"))
    }

    func testProbeRedactsEveryValueOutsideTheAllowlist() {
        // Review r1: an allowlist, not a denylist — a player may echo the link under any name
        // (`url`, `playUrl`, …), and every such value carries the debrid token. The NAMES stay
        // visible: learning which names SenPlayer sends is what the probe is for.
        let callback = url("\(installScheme)://external-player/senplayer/SESSION/success?url=https%3A%2F%2Fcdn.example.com%2Frealdebrid%2FSECRET%2Ffile.mkv&playUrl=https%3A%2F%2Fcdn.example.com%2FSECRET2&position=42.5&duration=5400&currentTime=7")
        let printed = ExternalPlaybackReturnRouter.redactedForProbe(callback)
        XCTAssertFalse(printed.contains("SECRET"))
        XCTAssertFalse(printed.contains("cdn.example.com"))
        XCTAssertTrue(redactedValue("url", in: printed), printed)
        XCTAssertTrue(redactedValue("playUrl", in: printed), printed)
        XCTAssertTrue(redactedValue("currentTime", in: printed), "an unknown numeric name is still redacted; the name shows: \(printed)")
        XCTAssertTrue(printed.contains("position=42.5"))
        XCTAssertTrue(printed.contains("duration=5400"))
    }

    func testProbeAllowlistIsCaseInsensitiveAndErrorFieldsStayReadable() {
        let callback = url("\(installScheme)://external-player/senplayer/SESSION/error?LASTPLAYEDURL=x&POSITION=3&errorCode=12&errorMessage=Not%20found&x-source=nuviotv")
        let printed = ExternalPlaybackReturnRouter.redactedForProbe(callback)
        XCTAssertFalse(printed.contains("LASTPLAYEDURL=x"))
        XCTAssertTrue(printed.contains("POSITION=3"))
        XCTAssertTrue(printed.contains("errorCode=12"))
        XCTAssertTrue(printed.contains("errorMessage=Not%20found"))
        XCTAssertTrue(printed.contains("x-source=nuviotv"))
        XCTAssertEqual(ExternalPlaybackReturnRouter.redactedForProbe(url("\(installScheme)://external-player/senplayer/SESSION/error")),
                       "\(installScheme)://external-player/senplayer/SESSION/error")
    }

    // MARK: - DeepLink.parse

    func testParseStillReadsTopShelfTitleLinks() {
        let link = DeepLink.parse(url("nuviotv://title?id=tt0111161&type=movie&name=Shawshank"), callbackScheme: installScheme)
        guard case .title(let preview)? = link else { return XCTFail("expected .title, got \(String(describing: link))") }
        XCTAssertEqual(preview.id, "tt0111161")
        XCTAssertEqual(preview.type, "movie")
        XCTAssertEqual(preview.name, "Shawshank")
    }

    func testParseStillReadsTopShelfResumeLinks() {
        let link = DeepLink.parse(
            url("nuviotv://resume?videoId=tt0903747:2:3&type=series&title=Breaking%20Bad&parentMetaId=tt0903747&season=2&episode=3"),
            callbackScheme: installScheme
        )
        guard case .resume(let type, let videoId, let title, let parentMetaId, let season, let episode)? = link else {
            return XCTFail("expected .resume, got \(String(describing: link))")
        }
        XCTAssertEqual(type, "series")
        XCTAssertEqual(videoId, "tt0903747:2:3")
        XCTAssertEqual(title, "Breaking Bad")
        XCTAssertEqual(parentMetaId, "tt0903747")
        XCTAssertEqual(season, 2)
        XCTAssertEqual(episode, 3)
    }

    func testParseNeverTurnsAnExternalPlayerCallbackIntoACover() {
        let paths = [
            "external-player/infuse/SESSION/success?lastPlayedUrl=https%3A%2F%2Fx&position=42",
            "external-player/infuse/SESSION/error",
        ]
        for scheme in ["nuviotv", installScheme] {
            for path in paths {
                XCTAssertNil(DeepLink.parse(url("\(scheme)://\(path)"), callbackScheme: installScheme), "\(scheme)://\(path)")
            }
        }
    }

    func testParseAcceptsATitleLinkOnTheCallbackScheme() {
        let link = DeepLink.parse(url("\(installScheme)://title?id=tt0111161&type=movie"), callbackScheme: installScheme)
        guard case .title(let preview)? = link else { return XCTFail("expected .title, got \(String(describing: link))") }
        XCTAssertEqual(preview.id, "tt0111161")
        // Case-insensitive, like the system's own scheme matching.
        XCTAssertNotNil(DeepLink.parse(url("COM.YOUNGCHRIS29.NUVIOTV://title?id=tt0111161"), callbackScheme: installScheme))
    }

    func testParseRejectsAForeignScheme() {
        XCTAssertNil(DeepLink.parse(url("com.someone.else://title?id=tt0111161&type=movie"), callbackScheme: installScheme))
        XCTAssertNil(DeepLink.parse(url("https://title?id=tt0111161&type=movie"), callbackScheme: installScheme))
    }
}
