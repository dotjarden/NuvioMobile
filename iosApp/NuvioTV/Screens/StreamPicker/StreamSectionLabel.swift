import SwiftUI

/// Stream picker A, P3 (decision D5): a small, non-focusable label before a section's rows
/// (upstream mobile's `StreamSectionHeader`). Add-on mode: the add-on's name in the "All" view with
/// its own "Fetching…" spinner while it is still answering, hidden under a chip. Quality mode
/// (polish D4): the tier name and row count ("4K · 12"), no spinner, also under a chip.
struct StreamSectionLabel: View {
    let name: String
    let isLoading: Bool
    /// Polish D4: the tier's row count; nil for add-on labels.
    var count: Int? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(name)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            if let count {
                Text(verbatim: "· \(count)")
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
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
        .accessibilityLabel(Text(verbatim: count.map { "\(name) · \($0)" } ?? name))
        .accessibilityIdentifier("stream_picker_section_label")
    }
}
