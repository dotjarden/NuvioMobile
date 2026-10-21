import SwiftUI
import XCTest
@testable import NuvioTV

/// W3-2 (b): the destructive row keeps the system red at rest and flips to the dark-on-white ink
/// on the focus platter.
final class SettingsDestructiveInkTests: XCTestCase {

    func testAtRestKeepsTheSystemRole() {
        let ink = SettingsDestructiveInk.colors(focused: false)
        XCTAssertNil(ink.title)
        XCTAssertEqual(ink.glyph, Color.red)
    }

    func testOnThePlatterTitleIsPrimaryAndGlyphIsDarkRed() {
        let ink = SettingsDestructiveInk.colors(focused: true)
        XCTAssertEqual(ink.title, Color.primary)
        XCTAssertEqual(ink.glyph, Color(red: 0xD7 / 255, green: 0, blue: 0x15 / 255))
        XCTAssertEqual(ink.glyph, SettingsDestructiveInk.platterRed)
    }
}
