import SharedCore
import SwiftUI

/// The mpv player's fourth panel tab ("Playback"): what its old swipe-up settings menu carried
/// beyond tracks — playback speed, subtitle/audio delay, the diagnostics overlay toggle, an
/// episode jump list and alternate sources — laid out as three columns inside the top panel.
/// The speed row and the Episodes / Sources columns live in `PlayerPlaybackColumns.swift`,
/// shared with the native engine's `NativePlaybackTab` (P4 A8).
/// Same rules as the other tabs: default tvOS button focus, Theme tokens, no accent.
struct MPVPlaybackTab: View {
    @ObservedObject var state: MPVPlaybackState
    @ObservedObject var engine: NextEpisodeEngine
    /// True when the presenter can swap playback contexts (episode jump / source switching).
    let canSwitchStreams: Bool
    /// Closes the panel after an action that replaces playback (episode jump, source switch).
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            settingsColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            if canSwitchStreams, !PlayerEpisodesColumn.sortedEpisodes(engine).isEmpty {
                PlayerEpisodesColumn(engine: engine, onClose: onClose)
                    .frame(width: 440)
                    .focusSection()
            }
            if canSwitchStreams {
                PlayerSourcesColumn(engine: engine, onClose: onClose)
                    .frame(width: 560)
                    .focusSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 520, alignment: .topLeading)
    }

    // MARK: - Speed · timing · diagnostics

    private var settingsColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                PlayerPanelSectionCaption(text: String(localized: "Playback Speed"))
                PlayerSpeedRow(current: state.playbackSpeed) { state.setSpeed?($0) }

                // Subtitle delay moved to the Subtitles tab's "Timing" row (beta.15 §B1) — that's
                // where a viewer actually looks when subs are out of sync, and it now persists
                // per title/profile. Audio delay stays here and persists per title/profile, like the subtitle delay.
                PlayerPanelSectionCaption(text: String(localized: "Timing")).padding(.top, Theme.Spacing.sm)
                delayRow(title: String(localized: "Audio Delay"), value: state.audioDelaySec, step: 0.25, limit: 10) {
                    state.setAudioDelay?($0)
                }
                Text("Positive values delay the track; negative values play it earlier.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)

                PlayerPanelSectionCaption(text: String(localized: "Diagnostics")).padding(.top, Theme.Spacing.sm)
                Button { state.showStreamInfo.toggle() } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: state.showStreamInfo ? "checkmark.circle.fill" : "info.circle")
                        Text(state.showStreamInfo ? String(localized: "Hide Stream Info") : String(localized: "Show Stream Info"))
                    }
                    .font(Theme.Font.body)
                }
                .accessibilityIdentifier("player.panel.diagnostics")
            }
        }
    }

    private func delayRow(title: String, value: Double, step: Double, limit: Double,
                          apply: @escaping (Double) -> Void) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 260, alignment: .leading)
            Button { apply(max(-limit, value - step)) } label: { Image(systemName: "minus") }
            Text(value == 0 ? "0.00 s" : String(format: "%+.2f s", value))
                .font(Theme.Font.body.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 150)
            Button { apply(min(limit, value + step)) } label: { Image(systemName: "plus") }
            if value != 0 {
                Button(String(localized: "Reset")) { apply(0) }.font(Theme.Font.meta)
            }
        }
    }
}
