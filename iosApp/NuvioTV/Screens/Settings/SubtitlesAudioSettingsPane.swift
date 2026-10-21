import SwiftUI
import SharedCore

/// "Subtitles & Audio" category content (detail-settings-revamp W2-C): subtitle appearance and
/// the audio/subtitle language preference, split out of `PlaybackSettingsPane` with logic and
/// wiring unchanged. Returns ROWS ONLY; the pane scaffold supplies the List.
struct SubtitlesAudioSettingsPane: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        SettingsSection(String(localized: "Subtitles")) {
            if let style = model.subtitleStyle {
                SubtitleAppearanceControls(
                    style: style,
                    onTextColor: { model.setSubtitleTextColor($0) },
                    onSize: { model.setSubtitleFontSize($0) },
                    onBackground: { model.setSubtitleBackground($0) },
                    onBold: { model.setSubtitleBold($0) },
                    onOutline: { model.setSubtitleOutline($0) },
                    onStripSdh: { model.setSubtitleStripSdh($0) }
                )
            } else {
                Text("Loading subtitle settings\u{2026}")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }

        SettingsSection(String(localized: "Audio & Subtitle Language")) {
            Text("When playback starts, auto-select the audio and subtitle tracks in your preferred language (when a matching track exists).")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: 1100, alignment: .leading)
            // FEAT-84: the shared 78-language list, A–Z in the app's language, sentinels on top
            // (see `LanguageOptions`). Each primary picker has its fallback row under it.
            SettingsPickerRow(
                title: String(localized: "Audio"),
                selection: Binding(get: { model.preferredAudioLanguage }, set: { model.setPreferredAudioLanguage($0) }),
                options: LanguageOptions.codes(LanguageOptions.audioCodes, keeping: model.preferredAudioLanguage, pinned: 2),
                descriptionID: .subtitlesAudioLanguage,
                label: LanguageOptions.name(forCode:)
            )
            SettingsPickerRow(
                title: String(localized: "Fallback Audio Language"),
                selection: Binding(get: { model.secondaryPreferredAudioLanguage }, set: { model.setSecondaryPreferredAudioLanguage($0) }),
                options: LanguageOptions.codes(LanguageOptions.fallbackAudioCodes, keeping: model.secondaryPreferredAudioLanguage, pinned: 2),
                descriptionID: .subtitlesFallbackAudioLanguage,
                label: LanguageOptions.name(forCode:)
            )
            SettingsPickerRow(
                title: String(localized: "Subtitles"),
                selection: Binding(get: { model.preferredSubtitleLanguage }, set: { model.setPreferredSubtitleLanguage($0) }),
                options: LanguageOptions.codes(LanguageOptions.subtitleCodes, keeping: model.preferredSubtitleLanguage, pinned: 2),
                descriptionID: .subtitlesSubtitleLanguage,
                label: LanguageOptions.name(forCode:)
            )
            // Off stays Off: with Subtitles = Off the players ignore the fallback
            // (`SubtitleFallbackGuard`), so the row is hidden then. Hidden, never disabled (a
            // disabled row is skipped by focus and reads as broken); focus is on the Subtitles
            // Menu when it goes, so nothing focused leaves the hierarchy.
            if model.preferredSubtitleLanguage != SubtitleLanguageOption.shared.NONE {
                SettingsPickerRow(
                    title: String(localized: "Fallback Subtitle Language"),
                    selection: Binding(get: { model.secondaryPreferredSubtitleLanguage }, set: { model.setSecondaryPreferredSubtitleLanguage($0) }),
                    options: LanguageOptions.codes(LanguageOptions.fallbackSubtitleCodes, keeping: model.secondaryPreferredSubtitleLanguage, pinned: 1),
                    descriptionID: .subtitlesFallbackSubtitleLanguage,
                    label: LanguageOptions.name(forCode:)
                )
            }
        }
    }
}

/// Subtitle appearance controls: a live preview plus text color, size, background, bold and outline.
/// Colors are `SubtitleColor` argb longs (0xAARRGGBB). The player reads these on the next file load.
/// Text Color stays a custom swatch row: the kit has no colour-swatch primitive.
private struct SubtitleAppearanceControls: View {
    let style: SubtitleStyleState
    let onTextColor: (Int64) -> Void
    let onSize: (Int32) -> Void
    let onBackground: (Int64) -> Void
    let onBold: (Bool) -> Void
    let onOutline: (Bool) -> Void
    let onStripSdh: (Bool) -> Void

    private let textColors: [(name: String, argb: Int64)] = [
        ("White", 0xFFFFFFFF), ("Yellow", 0xFFFFFF00), ("Cyan", 0xFF00FFFF), ("Green", 0xFF00FF00)
    ]
    private let sizes: [(name: String, sp: Int32)] = [
        (String(localized: "Small"), 14), (String(localized: "Medium"), 18),
        (String(localized: "Large"), 24), (String(localized: "X-Large"), 30)
    ]
    private let backgrounds: [(name: String, argb: Int64)] = [
        (String(localized: "Off"), 0x00000000), (String(localized: "Semi"), 0x80000000), (String(localized: "Solid"), 0xFF000000)
    ]

    var body: some View {
        preview

        controlRow(String(localized: "Text Color")) {
            ForEach(textColors, id: \.argb) { entry in
                Button { onTextColor(entry.argb) } label: {
                    SubtitleColorSwatch(
                        fill: color(entry.argb),
                        colorHex: UInt32(entry.argb & 0xFFFFFF),
                        isSelected: style.textColor == entry.argb
                    )
                }
                .buttonStyle(.borderless)
            }
        }

        SettingsPickerRow(
            title: String(localized: "Size"),
            selection: Binding(get: { style.fontSizeSp }, set: { onSize($0) }),
            options: sizes.map(\.sp),
            descriptionID: .subtitlesSize,
            label: { sp in sizes.first { $0.sp == sp }?.name ?? "\(sp)" }
        )

        SettingsPickerRow(
            title: String(localized: "Background"),
            selection: Binding(get: { style.backgroundColor }, set: { onBackground($0) }),
            options: backgrounds.map(\.argb),
            descriptionID: .subtitlesBackground,
            label: { argb in backgrounds.first { $0.argb == argb }?.name ?? "\(argb)" }
        )

        SettingsToggleRow(
            title: String(localized: "Bold"),
            subtitle: String(localized: "Use a heavier subtitle font"),
            isOn: Binding(get: { style.bold }, set: { onBold($0) }),
            descriptionID: .subtitlesBold
        )
        SettingsToggleRow(
            title: String(localized: "Outline"),
            subtitle: String(localized: "Draw an outline around text for readability"),
            isOn: Binding(get: { style.outlineEnabled }, set: { onOutline($0) }),
            descriptionID: .subtitlesOutline
        )
        SettingsToggleRow(
            title: String(localized: "Strip SDH Subtitles"),
            subtitle: String(localized: "Hide sound descriptions and speaker labels from text subtitles."),
            isOn: Binding(get: { style.stripSdh }, set: { onStripSdh($0) }),
            descriptionID: .subtitlesStripSdh
        )
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Color.black)
            Text("The quick brown fox")
                .font(style.bold ? Theme.Font.sectionTitle : Theme.Font.body)
                .foregroundStyle(color(style.textColor))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(color(style.backgroundColor))
        }
        .frame(height: 130)
        .frame(maxWidth: 700)
    }

    @ViewBuilder
    private func controlRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.md) { content() }
        }
    }

    private func color(_ argb: Int64) -> Color {
        Color(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255.0,
            green: Double((argb >> 8) & 0xFF) / 255.0,
            blue: Double(argb & 0xFF) / 255.0,
            opacity: Double((argb >> 24) & 0xFF) / 255.0
        )
    }
}

/// A subtitle text-color swatch: selection wears a ring that contrasts with the swatch's own
/// fill; focus wears a slightly lighter ring in the same contrast colour (the Appearance theme
/// swatch's rule, `AppearanceSettingsPane.SwatchLabel`) AND lifts the circle (`SubtitleSwatchFocusLift`).
/// BUG-201 (GitHub #9): this swatch read `\.isFocused` and never used it, so focus was invisible.
/// The ring alone is not enough: `SwatchLabel` checks selection first, so a swatch that is focused
/// AND selected looked the same as one that is only selected, and focus usually lands on the
/// selected swatch. The lift is the cue that holds in every state. Reports "Text Color" to the
/// Settings explainer while focused.
private struct SubtitleColorSwatch: View {
    let fill: Color
    /// Raw RGB backing `fill`, so the selection ring can pick a shade that stays visible against it.
    let colorHex: UInt32
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `strokeBorder` (inside the circle), as the Appearance swatch draws it, so the ring never
    /// grows past the 46 pt frame and the lift's scale is the only thing that changes the footprint.
    private var ringColor: Color {
        let contrast = Theme.Palette.onColor(forFillHex: colorHex)
        if isSelected { return contrast }
        return isFocused ? contrast.opacity(0.8) : Theme.Palette.textSecondary.opacity(0.4)
    }

    private var ringWidth: CGFloat {
        if isSelected { return 4 }
        return isFocused ? 3 : 1
    }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 46, height: 46)
            .overlay(Circle().strokeBorder(ringColor, lineWidth: ringWidth))
            .modifier(SubtitleSwatchFocusLift())
            .padding(Theme.Spacing.xs)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
            .settingsDescription(.subtitlesTextColor, title: String(localized: "Text Color"), systemImage: "textformat")
    }
}

/// Focus lift for the subtitle colour swatches: a private copy of `ProfileSelectionView`'s
/// `SwatchFocusLift` (x1.2 and a shadow). `.borderless` lifts only the IMAGES in a label, so a
/// plain coloured circle gets no system focus indication on the Apple TV (device pass 2026-10-17).
/// At 46 pt the x1.2 scale grows each side by 4.6 pt, inside the swatch's 8 pt padding, so it
/// never reaches the neighbouring swatch (16 pt gap plus its own padding). The animation is
/// dropped under Reduce Motion; the scale and shadow still apply, instantly.
private struct SubtitleSwatchFocusLift: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.2 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.55 : 0), radius: isFocused ? 14 : 0, y: isFocused ? 8 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
    }
}
