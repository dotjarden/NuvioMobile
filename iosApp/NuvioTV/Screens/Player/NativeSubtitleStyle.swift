import AVFoundation
import CoreMedia
import SharedCore

/// P4 (A9): the app's subtitle style (Settings › Subtitles, the shared `SubtitleStyleState` the mpv
/// player applies through `sub-*` properties) mapped onto CMTextMarkup attributes for the native
/// engine's `AVPlayerItem.textStyleRules`. Pure, so it unit-tests without a player.
///
/// Mapping (spec §3.1): text colour → `ForegroundColorARGB`; background → the per-glyph box
/// `CharacterBackgroundColorARGB` (mpv's `sub-back-color`; `BackgroundColorARGB` would paint the
/// whole caption window), omitted at alpha 0; outline on/off → `CharacterEdgeStyle` Uniform/None;
/// bold → `BoldStyle` (omitted when off); size → `RelativeFontSize` = sp / 18 × 100 clamped to
/// 65…222 % (omitted at exactly 100). Outline colour/width and the bottom offset have no
/// CMTextMarkup key and stay mpv-only (§3.4).
nonisolated enum NativeSubtitleStyle {
    struct Input: Equatable {
        var textARGB: Int64
        var backgroundARGB: Int64
        var outlineEnabled: Bool
        var bold: Bool
        var fontSizeSp: Int

        static let `default` = Input(textARGB: 0xFFFF_FFFF, backgroundARGB: 0, outlineEnabled: true,
                                     bold: false, fontSizeSp: 18)
    }

    static let minRelativeSize = 65.0
    static let maxRelativeSize = 222.0

    static func input(from s: SubtitleStyleState) -> Input {
        Input(textARGB: s.textColor, backgroundARGB: s.backgroundColor, outlineEnabled: s.outlineEnabled,
              bold: s.bold, fontSizeSp: Int(s.fontSizeSp))
    }

    /// `[a, r, g, b]`, each 0…1 (CMTextMarkup's ARGB array order).
    static func argbComponents(_ argb: Int64) -> [Double] {
        [(argb >> 24) & 0xFF, (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF].map { Double($0) / 255.0 }
    }

    /// Relative font size in percent, rounded, clamped to 65…222.
    static func relativeSize(sp: Int) -> Double {
        min(maxRelativeSize, max(minRelativeSize, (Double(sp) / 18.0 * 100.0).rounded()))
    }

    static func attributes(_ i: Input) -> [String: Any] {
        var a: [String: Any] = [:]
        a[kCMTextMarkupAttribute_ForegroundColorARGB as String] = argbComponents(i.textARGB)
        if (i.backgroundARGB >> 24) & 0xFF != 0 {
            a[kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String] = argbComponents(i.backgroundARGB)
        }
        a[kCMTextMarkupAttribute_CharacterEdgeStyle as String] = i.outlineEnabled
            ? kCMTextMarkupCharacterEdgeStyle_Uniform as String
            : kCMTextMarkupCharacterEdgeStyle_None as String
        if i.bold { a[kCMTextMarkupAttribute_BoldStyle as String] = kCFBooleanTrue as Any }
        let size = relativeSize(sp: i.fontSizeSp)
        if size != 100 { a[kCMTextMarkupAttribute_RelativeFontSize as String] = size }
        return a
    }

    /// One nil-selector rule (the attributes apply as defaults to every cue). Never empty in
    /// practice: the foreground and edge keys are always present, so the system default style is
    /// replaced on purpose, as mpv applies its default style too (§3.2).
    static func rules(_ i: Input) -> [AVTextStyleRule] {
        let attrs = attributes(i)
        guard !attrs.isEmpty, let rule = AVTextStyleRule(textMarkupAttributes: attrs) else { return [] }
        return [rule]
    }

    static func hex(_ argb: Int64) -> String {
        String(format: "#%02X%02X%02X%02X", (argb >> 24) & 0xFF, (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)
    }

    /// `[Subs] style rule fg=#FFFFFF00 bg=#00000000 edge=uniform bold=1 size=133%`
    static func logLine(_ i: Input) -> String {
        "[Subs] style rule fg=\(hex(i.textARGB)) bg=\(hex(i.backgroundARGB)) edge=\(i.outlineEnabled ? "uniform" : "none") "
            + "bold=\(i.bold ? 1 : 0) size=\(Int(relativeSize(sp: i.fontSizeSp)))%"
    }
}
