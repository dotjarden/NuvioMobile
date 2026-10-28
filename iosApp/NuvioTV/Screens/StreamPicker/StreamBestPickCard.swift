import SwiftUI

/// Direction C D3: the best-pick card. One focusable `.settingsRow` button on a `surface` card.
/// `Equatable` over its values (BUG-207): the closure is not compared, and the body computes
/// nothing; every string comes from the model or `StreamPickerCopy`.
struct StreamBestPickCard: View, Equatable {
    enum Metrics {
        static let vertical: CGFloat = 22
        static let horizontal: CGFloat = 26
        static let playCircle: CGFloat = 56
    }

    let model: StreamBestPickModel
    /// `StreamPickerResume.label(...)`, shown after the kicker; nil when there is nothing to resume.
    let resumeLabel: String?
    /// True while the picker is resolving this card's stream (spinner at the trailing edge).
    let isResolving: Bool
    let onSelect: () -> Void

    nonisolated static func == (lhs: StreamBestPickCard, rhs: StreamBestPickCard) -> Bool {
        lhs.model == rhs.model && lhs.resumeLabel == rhs.resumeLabel && lhs.isResolving == rhs.isResolving
    }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyCounter.tick("StreamBestPickCard")
        #endif
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                playCircle
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(verbatim: StreamPickerCopy.kicker(settled: model.isSettled, resumeLabel: resumeLabel))
                        .font(Theme.Font.caption)
                        .textCase(.uppercase)
                        .rowTextColor(secondary: true)
                        .lineLimit(1)
                    Text(verbatim: model.headline)
                        .font(Theme.Font.sectionTitle.weight(.bold))
                        .rowTextColor()
                        .lineLimit(1)
                    if let facts = model.facts {
                        Text(verbatim: facts)
                            .font(Theme.Font.meta)
                            .rowTextColor(secondary: true)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(verbatim: model.rankLine)
                        .font(Theme.Font.caption)
                        .rowTextColor(secondary: true)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isResolving {
                    ProgressView()
                }
            }
            .padding(.vertical, Metrics.vertical)
            .padding(.horizontal, Metrics.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transaction { $0.animation = nil }
        }
        .buttonStyle(.settingsRow)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .accessibilityLabel(Text(verbatim: StreamPickerCopy.cardSpokenLabel(model, resumeLabel: resumeLabel)))
        .accessibilityIdentifier("stream_picker_best_pick")
    }

    /// 56 pt circle in the style's foreground colour with a play glyph in the background colour, so
    /// both flip with the row style (light at rest, dark on the focus platter).
    private var playCircle: some View {
        Circle()
            .fill(.primary)
            .frame(width: Metrics.playCircle, height: Metrics.playCircle)
            .overlay(
                Image(systemName: "play.fill")
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(.background)
            )
            .accessibilityHidden(true)
    }
}
