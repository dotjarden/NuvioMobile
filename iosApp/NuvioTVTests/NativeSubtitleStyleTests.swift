import AVFoundation
import CoreMedia
import SharedCore
import XCTest
@testable import NuvioTV

final class NativeSubtitleStyleTests: XCTestCase {
    private func style(size: Int32 = 24, outline: Bool = true) -> SubtitleStyleState {
        SubtitleStyleState(textColor: 0xFFFFFF00, backgroundColor: 0x80000000,
            outlineColor: 0xFF000000, outlineEnabled: outline, outlineWidth: 2, bold: true,
            fontSizeSp: size, bottomOffset: 0, stripSdh: false,
            useForcedSubtitles: false, showOnlyPreferredLanguages: false)
    }

    func testSettingsErrorsKeepActionableMessagesWithoutTransportDump() {
        XCTAssertEqual(SettingsErrorMessage.readable("  Invalid API key.  ", fallback: "Try again."), "Invalid API key.")
        XCTAssertEqual(SettingsErrorMessage.readable("Exception in http request: Error Domain=NSURLErrorDomain UserInfo=...", fallback: "Check the URL."), "Check the URL.")
        XCTAssertEqual(SettingsErrorMessage.readable(String(repeating: "x", count: 300), fallback: "Try again."), "Try again.")
    }

    @MainActor func testAppearanceReachesActualAVPlayerItem() {
        let item = AVPlayerItem(asset: AVMutableComposition())
        NativeSubtitleStyle.apply(style(), to: item)
        let attributes = item.textStyleRules?.first?.textMarkupAttributes
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_ForegroundColorARGB as String] as? [Double], [1, 1, 1, 0])
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_BackgroundColorARGB as String] as? [Double], [128.0 / 255, 0, 0, 0])
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_BoldStyle as String] as? Bool, true)
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_RelativeFontSize as String] as? Double ?? 0, 133.333333, accuracy: 0.001)
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_CharacterEdgeStyle as String] as? String, kCMTextMarkupCharacterEdgeStyle_Uniform as String)
    }

    @MainActor func testChangingAppearanceReplacesPriorRules() {
        let item = AVPlayerItem(asset: AVMutableComposition())
        NativeSubtitleStyle.apply(style(), to: item)
        NativeSubtitleStyle.apply(style(size: 18, outline: false), to: item)
        XCTAssertEqual(item.textStyleRules?.count, 1)
        let attributes = item.textStyleRules?.first?.textMarkupAttributes
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_RelativeFontSize as String] as? Double, 100)
        XCTAssertEqual(attributes?[kCMTextMarkupAttribute_CharacterEdgeStyle as String] as? String, kCMTextMarkupCharacterEdgeStyle_None as String)
    }
}
