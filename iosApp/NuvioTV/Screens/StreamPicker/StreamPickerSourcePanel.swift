import SwiftUI

/// What the source panel's body holds. Direction A renders the stream list; Direction B (best
/// source + quality tiers) adds a `.tiers` case and swaps the body, not the layout.
enum StreamPickerSourceContent: Equatable {
    case list
}

/// Stream picker A, P1: the right pane (60 % of the screen). One rounded panel on
/// `Theme.Surface.panel` (the token's own comment names this screen), inner padding `md`, holding
/// in order a header (the resume pill and the chip row, P2/P3; today the credential banner), the
/// scrolling body, and a footer. Padding `screen` from the top, trailing and bottom screen edges;
/// the info panel supplies the leading gap. The panel is one focus section so Up/Down stay inside
/// the list and never wander into the static info pane.
///
/// Review r1 (P2): the header and footer get the panel's inset; the body runs edge to edge and
/// insets its own scroll content (`contentMargins`), so a focused row's 1.02 lift and shadow have
/// room inside the ScrollView's clip instead of being cut flat at the panel edge.
struct StreamPickerSourcePanel<Header: View, PanelBody: View, Footer: View>: View {
    let content: StreamPickerSourceContent
    @ViewBuilder let header: () -> Header
    @ViewBuilder let panelBody: () -> PanelBody
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header()
                .padding(.horizontal, Theme.Spacing.md)
            panelBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer()
                .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .padding([.top, .trailing, .bottom], Theme.Spacing.screen)
        .focusSection()
        .accessibilityIdentifier("stream_picker_source_panel")
    }

    @ViewBuilder
    private var panelBackground: some View {
        if StreamPickerSourcePanelStyle.usesMaterial {
            Rectangle().fill(Theme.Surface.panel)
        } else {
            Theme.Palette.surface.opacity(0.72)
        }
    }
}

/// Knobs that do not depend on the panel's generic content.
nonisolated enum StreamPickerSourcePanelStyle {
    /// P4.2 fallback: when the material costs frames on the device over a 150-stream list, flip
    /// this to draw a flat `surface` at 0.72 behind the panel instead (Android TV below API 31).
    static let usesMaterial = true
}
