import SwiftUI
import XCTest
@testable import NuvioTV

/// W3-17 (BUG-205): the on/off state of Detail's compact action buttons is the glyph colour. The
/// whole table: focus wins (on-platter ink, active or not); at rest an active button shows the
/// accent and an inactive one the normal label colour.
@MainActor
final class DetailActiveGlyphTests: XCTestCase {
    private let accent = Color(.sRGB, red: 0.9, green: 0.2, blue: 0.2, opacity: 1)

    func testActiveAtRestIsTheAccent() {
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: false, accent: accent), accent)
    }

    func testInactiveAtRestIsTheNormalLabelColour() {
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: false, accent: accent),
                       DetailActiveGlyph.restingLabel)
        XCTAssertEqual(DetailActiveGlyph.restingLabel, Color.primary)
    }

    func testFocusedIsTheOnPlatterInkWhetherOrNotActive() {
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: true, accent: accent),
                       DetailActiveGlyph.inkOnPlatter)
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: true, accent: accent),
                       DetailActiveGlyph.inkOnPlatter)
    }

    /// The White theme's accent (near-white) must never reach the near-white focus platter.
    func testAWhiteAccentNeverShowsOnTheFocusedPlatter() {
        let white = Color(.sRGB, red: 0.96, green: 0.96, blue: 0.96, opacity: 1)
        XCTAssertNotEqual(DetailActiveGlyph.color(active: true, focused: true, accent: white), white)
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: true, accent: white),
                       DetailActiveGlyph.inkOnPlatter)
    }

    func testTheFocusedInkIsTheProminentLabelDark() {
        XCTAssertEqual(DetailActiveGlyph.inkOnPlatter, Color(hex: 0x0D0D0D))
    }

    /// Only the active/focused pair decides the colour: the accent argument is not read when
    /// focused or inactive.
    func testTheAccentIsReadOnlyForAnActiveButtonAtRest() {
        let other = Color(.sRGB, red: 0.1, green: 0.4, blue: 0.9, opacity: 1)
        XCTAssertEqual(DetailActiveGlyph.color(active: false, focused: false, accent: accent),
                       DetailActiveGlyph.color(active: false, focused: false, accent: other))
        XCTAssertEqual(DetailActiveGlyph.color(active: true, focused: true, accent: accent),
                       DetailActiveGlyph.color(active: true, focused: true, accent: other))
        XCTAssertNotEqual(DetailActiveGlyph.color(active: true, focused: false, accent: accent),
                          DetailActiveGlyph.color(active: true, focused: false, accent: other))
    }
}
