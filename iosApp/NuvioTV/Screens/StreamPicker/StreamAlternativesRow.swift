import SwiftUI

/// Direction C D4: the alternatives row under the best-pick card. System `.bordered` pills (their
/// own height), every pill but "Show all" leading, "Show all" trailing. Pills absent from
/// `alternatives` (no 1080p, no direct link) are simply not drawn. Takes values and a closure, no
/// view model; the pills share the picker's `FocusState` the way `SourceChipRow` does.
struct StreamAlternativesRow: View {
    let alternatives: [StreamAlternativeModel]
    let resolvingKey: String?
    let focus: FocusState<String?>.Binding
    let onSelect: (StreamAlternativeModel) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(alternatives.filter { $0.kind != .showAll }) { alt in
                pill(alt)
            }
            Spacer(minLength: Theme.Spacing.sm)
            ForEach(alternatives.filter { $0.kind == .showAll }) { alt in
                pill(alt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ alt: StreamAlternativeModel) -> some View {
        Button {
            onSelect(alt)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(verbatim: alt.title)
                    .font(Theme.Font.metaStrong)
                    .lineLimit(1)
                // C-27: the pill's own stream is resolving (it is often folded behind "N more").
                if let rowKey = alt.rowKey, rowKey == resolvingKey {
                    ProgressView().scaleEffect(0.5).frame(width: 18, height: 18)
                }
            }
        }
        .buttonStyle(.bordered)
        .focused(focus, equals: alt.focusKey)
        .accessibilityIdentifier(alt.accessibilityID)
    }
}
