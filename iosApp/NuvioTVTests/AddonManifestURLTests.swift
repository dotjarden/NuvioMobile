import XCTest
import SharedCore
@testable import NuvioTV

/// Add-ons hub C, H1: the manifest-URL rules the install field applies before calling the
/// repository (mirror of the shared `normalizeManifestUrl` plus the scheme rejection).
final class AddonManifestURLTests: XCTestCase {

    private func normalized(_ raw: String) throws -> String {
        try AddonManifestURL.normalize(raw)
    }

    func testStremioSchemeBecomesHttps() throws {
        XCTAssertEqual(try normalized("stremio://x.y/manifest.json"), "https://x.y/manifest.json")
    }

    func testWhitespaceIsTrimmedAndManifestAppended() throws {
        XCTAssertEqual(try normalized(" https://x.y/addon/ "), "https://x.y/addon/manifest.json")
    }

    func testBareHostGetsHttpsAndManifest() throws {
        XCTAssertEqual(try normalized("x.y/addon"), "https://x.y/addon/manifest.json")
    }

    func testFragmentIsDroppedAndQueryKept() throws {
        XCTAssertEqual(
            try normalized("https://x.y/addon/manifest.json?key=1#frag"),
            "https://x.y/addon/manifest.json?key=1"
        )
    }

    func testQueryIsReattachedAfterManifestSuffix() throws {
        XCTAssertEqual(try normalized("https://x.y/addon?key=1"), "https://x.y/addon/manifest.json?key=1")
    }

    func testOtherSchemeIsRejected() {
        XCTAssertThrowsError(try AddonManifestURL.normalize("ftp://x.y/manifest.json")) { error in
            XCTAssertEqual(error as? AddonManifestURL.Failure, .unsupportedScheme("ftp"))
        }
    }

    func testBlankInputIsEmpty() {
        XCTAssertThrowsError(try AddonManifestURL.normalize("   ")) { error in
            XCTAssertEqual(error as? AddonManifestURL.Failure, .empty)
        }
    }

    func testSameManifestIgnoresSchemeHostCaseAndTrailingSlash() {
        XCTAssertTrue(AddonManifestURL.isSameManifest("HTTPS://X.Y/addon", "https://x.y/addon/manifest.json/"))
    }

    func testDifferentPathsAreDifferentManifests() {
        XCTAssertFalse(AddonManifestURL.isSameManifest("https://x.y/a", "https://x.y/b"))
    }

    func testPathCaseIsSignificantAndFailuresNeverMatch() {
        XCTAssertFalse(AddonManifestURL.isSameManifest("https://x.y/Addon", "https://x.y/addon"))
        XCTAssertFalse(AddonManifestURL.isSameManifest("ftp://x.y/a", "ftp://x.y/a"))
    }

    func testMixedCaseSchemeIsLowercased() throws {
        XCTAssertEqual(try normalized("Https://x.y/a"), "https://x.y/a/manifest.json")
    }

    func testStremioSchemeKeepsQuery() throws {
        XCTAssertEqual(try normalized("stremio://x.y/a?k=1"), "https://x.y/a/manifest.json?k=1")
    }

    func testNormalizeIsIdempotent() throws {
        for input in ["x.y/a", "Https://x.y/a/?k=1#f", "stremio://x.y/a/manifest.json?k=1"] {
            let once = try normalized(input)
            XCTAssertEqual(try normalized(once), once, input)
        }
    }

    func testSchemeInsideQueryIsNotAScheme() throws {
        XCTAssertEqual(try normalized("x.y/a?u=http://z"), "https://x.y/a/manifest.json?u=http://z")
    }

    func testUserinfoCaseAndQueryAreSignificant() {
        XCTAssertFalse(AddonManifestURL.isSameManifest("https://Token@x.y/a", "https://token@x.y/a"))
        XCTAssertFalse(AddonManifestURL.isSameManifest("https://x.y/a?k=1", "https://x.y/a?k=2"))
        XCTAssertTrue(AddonManifestURL.isSameManifest("https://Token@X.Y/a", "https://Token@x.y/a"))
    }
}
