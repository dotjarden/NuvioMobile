import SwiftUI

/// Stream picker A, P3 (decision D5): in the "All" view a small, non-focusable label before each
/// add-on's rows (upstream mobile's `StreamSectionHeader`), with that add-on's own "Fetching…"
/// spinner while it is still answering. Hidden when a source chip is selected.
struct StreamSectionLabel: View {
    let name: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(name)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            if isLoading {
                ProgressView().scaleEffect(0.6)
                Text("Fetching\u{2026}")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.top, Theme.Spacing.sm)
        // Review r1: aligned with the row text, which sits `md` inside its card.
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stream_picker_section_label")
    }
}
