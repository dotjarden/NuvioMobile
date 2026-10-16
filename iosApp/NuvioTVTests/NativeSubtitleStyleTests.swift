import AVFoundation
import CoreMedia
import XCTest
@testable import NuvioTV

/// P4 (A9): the app subtitle style mapped onto CMTextMarkup attributes for the native engine.
final class NativeSubtitleStyleTests: XCTestCase {
    private let fg = kCMTextMarkupAttribute_ForegroundColorARGB as String
    private let cbg = kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String
    private let edge = kCMTextMarkupAttribute_CharacterEdgeStyle as String
    private let bold = kCMTextMarkupAttribute_BoldStyle as String
    private let size = kCMTextMarkupAttribute_RelativeFontSize as String

    private func input(text: Int64 = 0xFFFF_FFFF, bg: Int64 = 0, outline: Bool = true, bold: Bool = false, sp: Int = 18) -> NativeSubtitleStyle.Input {
        .init(textARGB: text, backgroundARGB: bg, outlineEnabled: outline, bold: bold, fontSizeSp: sp)
    }

    func testDefaults() {
        let a = NativeSubtitleStyle.attributes(input())
        XCTAssertEqual(a[fg] as? [Double], [1, 1, 1, 1])
        XCTAssertNil(a[cbg])
        XCTAssertEqual(a[edge] as? String, kCMTextMarkupCharacterEdgeStyle_Uniform as String)
        XCTAssertNil(a[bold])
        XCTAssertNil(a[size])
    }

    func testOutlineOffWithBackground() {
        let a = NativeSubtitleStyle.attributes(input(bg: 0x8000_0000, outline: false))
        XCTAssertEqual(a[edge] as? String, kCMTextMarkupCharacterEdgeStyle_None as String)
        let c = try! XCTUnwrap(a[cbg] as? [Double])
        XCTAssertEqual(c.count, 4)
        XCTAssertEqual(c[0], 0.502, accuracy: 0.002)
        XCTAssertEqual(c[1], 0); XCTAssertEqual(c[2], 0); XCTAssertEqual(c[3], 0)
    }

    func testSizes() {
        XCTAssertEqual(NativeSubtitleStyle.attributes(input(sp: 36))[size] as? Double, 200)
        XCTAssertEqual(NativeSubtitleStyle.attributes(input(sp: 6))[size] as? Double, 65)
        XCTAssertEqual(NativeSubtitleStyle.attributes(input(sp: 60))[size] as? Double, 222)
        XCTAssertNil(NativeSubtitleStyle.attributes(input(sp: 18))[size])
    }

    func testBold() {
        let a = NativeSubtitleStyle.attributes(input(bold: true))
        XCTAssertEqual((a[bold] as AnyObject) as? NSNumber, kCFBooleanTrue as NSNumber)
    }

    func testRulesAndLog() {
        XCTAssertEqual(NativeSubtitleStyle.rules(input()).count, 1)
        XCTAssertEqual(NativeSubtitleStyle.logLine(input(text: 0xFFFF_FF00, bold: true, sp: 24)),
                       "[Subs] style rule fg=#FFFFFF00 bg=#00000000 edge=uniform bold=1 size=133%")
    }
}
