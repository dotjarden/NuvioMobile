import XCTest
@testable import NuvioTV

/// beta.19-rc1 verdict (R1, BUG-132): which colour the morphed inline-trailer tile's focus ring wears.
/// Steven's 72 Heures / Elize frames: with "Focus Ring Takes Poster Color" on, the pink or gold ring
/// turned white the moment the trailer tile replaced the poster card, because the tile read neither
/// the setting nor `ArtworkColorStore`. The table mirrors `PosterCard`'s rule: the accent ring takes
/// precedence over No Zoom's still ring, and the poster colour replaces whichever ring can draw.
final class InlineTrailerTileTintTests: XCTestCase {

    /// Spelled out: a bare `.none` can resolve to `Optional.none` inside `XCTAssertEqual`'s generics.
    private let noRing = InlineTrailerTileTint.RingSource.none

    private func ring(setting: Bool = false, accent: Bool = false, noZoom: Bool = false,
                      focused: Bool = true, color: Bool = false) -> InlineTrailerTileTint.RingSource {
        InlineTrailerTileTint.ringSource(settingOn: setting, accentRing: accent, noZoom: noZoom,
                                         focused: focused, hasPosterColor: color)
    }

    func testSettingOffKeepsTheAccentRing() {
        // Even when the store has a colour for the art, the setting off draws what the tile always drew.
        XCTAssertEqual(ring(setting: false, accent: true, color: false), .accent)
        XCTAssertEqual(ring(setting: false, accent: true, color: true), .accent)
    }

    func testSettingOnAccentRingWithColorWearsThePosterColor() {
        XCTAssertEqual(ring(setting: true, accent: true, color: true), .poster)
    }

    func testSettingOnAccentRingWithGreyArtKeepsAccent() {
        // test87 skips on this: grey art has no colour, and the ring legitimately stays the accent colour.
        XCTAssertEqual(ring(setting: true, accent: true, color: false), .accent)
    }

    func testNoZoomRingWithoutColorIsTheStillRing() {
        XCTAssertEqual(ring(setting: true, noZoom: true, color: false), .still)
        XCTAssertEqual(ring(setting: false, noZoom: true, color: false), .still)
    }

    /// BUG-158 / D9: still mode (accent ring off) wears the poster colour whenever the store has
    /// one, whatever `focus_ring_poster_color` says; white only for colourless art.
    func testStillModeWearsPosterColourRegardlessOfTheSetting() {
        XCTAssertEqual(ring(setting: false, noZoom: true, color: true), .poster)
        XCTAssertEqual(ring(setting: true, noZoom: true, color: true), .poster)
        XCTAssertEqual(ring(setting: false, noZoom: true, color: false), .still)
    }

    func testSamplingTable() {
        // Accent ring on: only the setting decides (unchanged).
        XCTAssertFalse(FocusRingTintSampling.samples(settingOn: false, accentRing: true, noZoom: false))
        XCTAssertTrue(FocusRingTintSampling.samples(settingOn: true, accentRing: true, noZoom: false))
        XCTAssertFalse(FocusRingTintSampling.samples(settingOn: false, accentRing: true, noZoom: true))
        // Still mode, ring off: always samples (D9).
        XCTAssertTrue(FocusRingTintSampling.samples(settingOn: false, accentRing: false, noZoom: true))
        XCTAssertTrue(FocusRingTintSampling.samples(settingOn: true, accentRing: false, noZoom: true))
        // Zoom on, ring off: nothing to colour.
        XCTAssertFalse(FocusRingTintSampling.samples(settingOn: true, accentRing: false, noZoom: false))
        XCTAssertFalse(FocusRingTintSampling.samples(settingOn: false, accentRing: false, noZoom: false))
    }

    /// BUG-149: store logo first, then the item's own / metahub URL, else text.
    func testOverlayLogoResolutionOrder() {
        let fallback = URL(string: "https://images.metahub.space/logo/medium/tt1/img")
        XCTAssertEqual(InlineTrailerTitleOverlay.resolvedLogoURL(storeURL: "https://image.tmdb.org/l.png", fallbackURL: fallback)?.absoluteString,
                       "https://image.tmdb.org/l.png")
        XCTAssertEqual(InlineTrailerTitleOverlay.resolvedLogoURL(storeURL: nil, fallbackURL: fallback), fallback)
        XCTAssertEqual(InlineTrailerTitleOverlay.resolvedLogoURL(storeURL: "", fallbackURL: fallback), fallback)
        XCTAssertNil(InlineTrailerTitleOverlay.resolvedLogoURL(storeURL: nil, fallbackURL: nil))
    }

    func testNoZoomRingWithColorWearsThePosterColor() {
        XCTAssertEqual(ring(setting: true, noZoom: true, color: true), .poster)
    }

    func testAccentRingTakesPrecedenceOverNoZoom() {
        XCTAssertEqual(ring(setting: false, accent: true, noZoom: true), .accent)
        XCTAssertEqual(ring(setting: true, accent: true, noZoom: true, color: true), .poster)
    }

    func testRingOffAndZoomOnDrawsNoRing() {
        // The default look: the focused card lifts and nothing is stroked, whatever the setting says.
        XCTAssertEqual(ring(setting: true, color: true), noRing)
        XCTAssertEqual(ring(setting: false, color: false), noRing)
    }

    func testUnfocusedDrawsNoRing() {
        XCTAssertEqual(ring(setting: true, accent: true, focused: false, color: true), noRing)
        XCTAssertEqual(ring(setting: false, noZoom: true, focused: false), noRing)
    }

    func testRawValuesAreTheProbeSpelling() {
        // `debug_trailerTile ring=<…>` reads these (test87).
        XCTAssertEqual(InlineTrailerTileTint.RingSource.poster.rawValue, "poster")
        XCTAssertEqual(InlineTrailerTileTint.RingSource.accent.rawValue, "accent")
        XCTAssertEqual(InlineTrailerTileTint.RingSource.still.rawValue, "still")
        XCTAssertEqual(noRing.rawValue, "none")
    }
}
