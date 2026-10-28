import SwiftUI

/// Direction C D5: the "N more" row after a tier's previews. A full-width `.settingsRow` button with
/// no background at rest; Select expands the tier. `Equatable` over its values (the closure is not
/// compared).
struct StreamTierMoreRow: View, Equatable {
    /// The tier label or add-on name; only spoken, never drawn.
    let sectionTitle: String
    let hiddenCount: Int
    let onSelect: () -> Void

    nonisolated static func == (lhs: StreamTierMoreRow, rhs: StreamTierMoreRow) -> Bool {
        lhs.sectionTitle == rhs.sectionTitle && lhs.hiddenCount == rhs.hiddenCount
    }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyCounter.tick("StreamTierMoreRow")
        #endif
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.xs) {
                Spacer(minLength: 0)
                Text(verbatim: StreamPickerCopy.moreText(hiddenCount))
                    .font(Theme.Font.meta)
                Image(systemName: "chevron.right")
                    .font(Theme.Font.caption)
            }
            .rowTextColor(secondary: true)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .transaction { $0.animation = nil }
        }
        .buttonStyle(.settingsRow)
        .accessibilityLabel(Text(verbatim: StreamPickerCopy.moreSpokenLabel(sectionTitle: sectionTitle,
                                                                           hidden: hiddenCount)))
        .accessibilityIdentifier("stream_picker_tier_more")
    }
}
