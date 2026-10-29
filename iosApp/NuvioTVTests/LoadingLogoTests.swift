import XCTest
@testable import NuvioTV

/// BUG-184 (Steven, 2026-10-19): the loading screen shows the opening screen's (localized) logo.
final class LoadingLogoTests: XCTestCase {
    func testOpeningScreenLogoWins() {
        let url = PlayerLoadingOverlay.logoURL(logoUrl: "https://image.tmdb.org/t/p/w500/fr.png", parentMetaId: "tt123")
        XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/fr.png")
    }

    func testMissingLogoFallsBackToMetahub() {
        XCTAssertEqual(PlayerLoadingOverlay.logoURL(logoUrl: nil, parentMetaId: "tt123:1:2")?.absoluteString,
                       "https://images.metahub.space/logo/medium/tt123/img")
        XCTAssertEqual(PlayerLoadingOverlay.logoURL(logoUrl: "", parentMetaId: "tt123")?.absoluteString,
                       "https://images.metahub.space/logo/medium/tt123/img")
    }
}
