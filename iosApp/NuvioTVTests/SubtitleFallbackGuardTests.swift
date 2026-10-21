import XCTest
import SharedCore
@testable import NuvioTV

/// FEAT-84 "Off stays Off": the subtitle fallback never reaches the shared target resolver while
/// the primary Subtitles setting is Off (see `SubtitleFallbackGuard`).
final class SubtitleFallbackGuardTests: XCTestCase {
    func testOffDropsTheSecondary() {
        XCTAssertNil(SubtitleFallbackGuard.effectiveSecondary(primary: SubtitleLanguageOption.shared.NONE, secondary: "en"))
        // The primary is normalized like the shared rule: case and whitespace do not matter, and
        // a blank primary counts as Off.
        XCTAssertNil(SubtitleFallbackGuard.effectiveSecondary(primary: " NONE ", secondary: "en"))
        XCTAssertNil(SubtitleFallbackGuard.effectiveSecondary(primary: "", secondary: "en"))
    }

    func testDeviceAndLanguagesPassTheSecondaryThrough() {
        XCTAssertEqual(SubtitleFallbackGuard.effectiveSecondary(primary: SubtitleLanguageOption.shared.DEVICE, secondary: "en"), "en")
        XCTAssertEqual(SubtitleFallbackGuard.effectiveSecondary(primary: "en", secondary: "fr"), "fr")
        XCTAssertEqual(SubtitleFallbackGuard.effectiveSecondary(primary: "pt-br", secondary: "es-419"), "es-419")
        XCTAssertEqual(SubtitleFallbackGuard.effectiveSecondary(primary: SubtitleLanguageOption.shared.FORCED, secondary: "en"), "en")
    }

    func testNilStaysNil() {
        XCTAssertNil(SubtitleFallbackGuard.effectiveSecondary(primary: "en", secondary: nil))
        XCTAssertNil(SubtitleFallbackGuard.effectiveSecondary(primary: SubtitleLanguageOption.shared.NONE, secondary: nil))
    }

    /// The shared behaviour the guard covers (an upstream-report candidate): with the primary
    /// Off the shared resolver still returns the secondary as a target; through the guard the
    /// target list is empty, which both players treat as subtitles off.
    func testGuardEmptiesTheSharedTargetsWhenOff() {
        let unguarded = PlayerLanguagePreferencesKt.resolvePreferredSubtitleLanguageTargets(
            preferredSubtitleLanguage: SubtitleLanguageOption.shared.NONE,
            secondaryPreferredSubtitleLanguage: "en",
            deviceLanguages: ["en"]
        )
        XCTAssertEqual(unguarded, ["en"])
        let guarded = PlayerLanguagePreferencesKt.resolvePreferredSubtitleLanguageTargets(
            preferredSubtitleLanguage: SubtitleLanguageOption.shared.NONE,
            secondaryPreferredSubtitleLanguage: SubtitleFallbackGuard.effectiveSecondary(
                primary: SubtitleLanguageOption.shared.NONE, secondary: "en"
            ),
            deviceLanguages: ["en"]
        )
        XCTAssertEqual(guarded, [])
        // With a primary language the fallback still follows it.
        let withPrimary = PlayerLanguagePreferencesKt.resolvePreferredSubtitleLanguageTargets(
            preferredSubtitleLanguage: "fr",
            secondaryPreferredSubtitleLanguage: SubtitleFallbackGuard.effectiveSecondary(primary: "fr", secondary: "en"),
            deviceLanguages: []
        )
        XCTAssertEqual(withPrimary, ["fr", "en"])
    }
}
