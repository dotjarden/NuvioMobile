import SwiftUI
import UIKit
import XCTest
@testable import NuvioTV

/// W3-17 (BUG-205): the on/off state of Detail's compact action buttons is the glyph colour. The
/// whole table: focus wins (on-platter ink, active or not); at rest an active button shows the
/// accent and an inactive one the normal label colour, dimmed to the secondary colour beside a
/// light accent (review r1 P2-1). Shuffle carries its state in its glyph too.
@MainActor
final class DetailActiveGlyphTests: XCTestCase {
    private let accent = Color(.sRGB, red: 0.9, green: 0.2, blue: 0.2, opacity: 1)
    /// The theme accents `Theme.Palette.applyTheme(named:)` sets for WHITE and OCEAN.
    private let white = Color(hex: 0xF5F5F5)
    private let ocean = Color(hex: 0x1E88E5)

    func testActiveAtRestIsTheAccent() {
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: false, accent: accent), accent)
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: false, accent: white), white)
    }

    func testInactiveAtRestIsTheNormalLabelColour() {
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: false, accent: accent),
                       DetailActiveGlyph.restingLabel)
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: false, accent: ocean),
                       DetailActiveGlyph.restingLabel)
        XCTAssertEqual(DetailActiveGlyph.restingLabel, Color.primary)
    }

    /// Review r1 P2-1: beside the White accent the inactive label is the secondary label token.
    func testInactiveAtRestBesideALightAccentIsTheSecondaryLabelColour() {
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: false, accent: white),
                       DetailActiveGlyph.dimmedRestingLabel)
        XCTAssertEqual(DetailActiveGlyph.dimmedRestingLabel, Theme.Palette.textSecondary)
    }

    func testFocusedIsTheOnPlatterInkWhetherOrNotActive() {
        for accent in [accent, white, ocean] {
            XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: true, accent: accent),
                           DetailActiveGlyph.inkOnPlatter)
            XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: true, accent: accent),
                           DetailActiveGlyph.inkOnPlatter)
        }
    }

    /// The White theme's accent (near-white) must never reach the near-white focus platter.
    func testAWhiteAccentNeverShowsOnTheFocusedPlatter() {
        XCTAssertNotEqual(DetailActiveGlyph.color(active: true, focused: true, accent: white), white)
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: true, accent: white),
                       DetailActiveGlyph.inkOnPlatter)
    }

    func testTheFocusedInkIsTheProminentLabelDark() {
        XCTAssertEqual(DetailActiveGlyph.inkOnPlatter, Color(hex: 0x0D0D0D))
    }

    /// Only White crosses the light threshold; every saturated theme accent stays below it, so
    /// their inactive label is unchanged.
    func testOnlyTheWhiteAccentIsLight() {
        XCTAssertEqual(DetailActiveGlyph.luminance(of: white), 0.96, accuracy: 0.01)
        XCTAssertTrue(DetailActiveGlyph.isLight(white))
        let saturated: [UInt32] = [0xE53935, 0x1E88E5, 0x8E24AA, 0x43A047, 0xFB8C00, 0xD81B60]
        for hex in saturated {
            XCTAssertFalse(DetailActiveGlyph.isLight(Color(hex: hex)), String(format: "%06X", hex))
        }
        // Same scale as the repo's hex luminance (`Theme.Palette.luminance(fromHexString:)`).
        for hex: UInt32 in [0xF5F5F5, 0x1E88E5, 0xFB8C00] {
            let expected = Theme.Palette.luminance(fromHexString: String(format: "%06X", hex)) ?? -1
            XCTAssertEqual(DetailActiveGlyph.luminance(of: Color(hex: hex)), expected, accuracy: 0.005)
        }
    }

    /// For a saturated accent, only the active/focused pair decides the colour: the accent argument
    /// is not read when focused, nor (beyond its lightness) when inactive.
    func testTheAccentIsReadOnlyForAnActiveButtonAtRest() {
        let other = Color(.sRGB, red: 0.1, green: 0.4, blue: 0.9, opacity: 1)
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: false, accent: accent),
                       DetailActiveGlyph.color(active: false, focused: false, accent: other))
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: true, accent: accent),
                       DetailActiveGlyph.color(active: true, focused: true, accent: other))
        XCTAssertNotEqual(DetailActiveGlyph.color(active: true, focused: false, accent: accent),
                          DetailActiveGlyph.color(active: true, focused: false, accent: other))
    }

    // MARK: - On and off differ on screen (review r1 P2-1)

    /// At rest, the on and off label colours are told apart on the dark screen for the White
    /// accent and for Ocean: their contrast, composited over the app background, is at least 1.5:1
    /// (measured 2026-10-21 on the tvOS 26 simulator: White 3.36, Ocean 3.68). The pre-fix pair
    /// (White's accent against the normal label colour) is below it.
    func testOnAndOffDifferAtRestForWhiteAndOcean() {
        for (name, accent) in [("White", white), ("Ocean", ocean)] {
            let on = DetailActiveGlyph.color(active: true, focused: false, accent: accent)
            let off = DetailActiveGlyph.color(active: false, focused: false, accent: accent)
            let ratio = contrast(on, off)
            XCTAssertGreaterThanOrEqual(ratio, 1.5, "\(name): \(ratio)")
        }
        let undimmed = contrast(white, DetailActiveGlyph.restingLabel)
        XCTAssertLessThan(undimmed, 1.5, "without the dim, White's on and off are the same white: \(undimmed)")
    }

    /// Each button's (glyph, colour) pair differs between on and off, at rest and focused, for the
    /// White accent and for Ocean. Under focus both colours are the ink, so the glyph carries it.
    func testEachButtonsGlyphAndColourPairDiffersBetweenOnAndOff() {
        // (on, off) glyphs: Watched and Library as `DetailView` draws them, Shuffle from the helper.
        let buttons: [(String, String, String)] = [
            ("Watched", "checkmark.circle.fill", "checkmark.circle"),
            ("Library", "checkmark", "plus"),
            ("Shuffle", DetailActiveGlyph.shuffleOnGlyph, DetailActiveGlyph.shuffleOffGlyph),
        ]
        for (accentName, accent) in [("White", white), ("Ocean", ocean)] {
            for (button, onGlyph, offGlyph) in buttons {
                for focused in [false, true] {
                    let on = (DetailActiveGlyph.glyph(active: true, onGlyph: onGlyph, offGlyph: offGlyph),
                              DetailActiveGlyph.color(active: true, focused: focused, accent: accent))
                    let off = (DetailActiveGlyph.glyph(active: false, onGlyph: onGlyph, offGlyph: offGlyph),
                               DetailActiveGlyph.color(active: false, focused: focused, accent: accent))
                    XCTAssertNotEqual(on.0, off.0, "\(button) glyph, \(accentName), focused=\(focused)")
                    XCTAssertFalse(on.0 == off.0 && on.1 == off.1, "\(button), \(accentName), focused=\(focused)")
                }
            }
        }
    }

    func testGlyphPicksOnOrOff() {
        XCTAssertEqual(DetailActiveGlyph.glyph(active: true, onGlyph: "a", offGlyph: "b"), "a")
        XCTAssertEqual(DetailActiveGlyph.glyph(active: false, onGlyph: "a", offGlyph: "b"), "b")
    }

    /// Both Shuffle symbols exist in the tvOS SF Symbols set (a missing name draws nothing).
    func testShuffleGlyphsExistOnTvOS() {
        XCTAssertNotNil(UIImage(systemName: DetailActiveGlyph.shuffleOnGlyph))
        XCTAssertNotNil(UIImage(systemName: DetailActiveGlyph.shuffleOffGlyph))
        XCTAssertNotEqual(DetailActiveGlyph.shuffleOnGlyph, DetailActiveGlyph.shuffleOffGlyph)
    }

    // MARK: - Helpers

    /// WCAG contrast of two label colours composited over the app background (`#0D0D0D`), both
    /// resolved on the dark scheme the app pins.
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = compositedLuminance(a), lb = compositedLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG relative luminance of `color` over `#0D0D0D`: blended on the resolved (gamma-encoded)
    /// sRGB components, as the compositor blends, then linearised.
    private func compositedLuminance(_ color: Color) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let fg = color.resolve(in: environment)
        let bg = Color(hex: 0x0D0D0D).resolve(in: environment)
        let alpha = Double(fg.opacity)
        func linear(_ f: Float, _ b: Float) -> Double {
            let c = min(max(alpha * Double(f) + (1 - alpha) * Double(b), 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(fg.red, bg.red) + 0.7152 * linear(fg.green, bg.green) + 0.0722 * linear(fg.blue, bg.blue)
    }
}
