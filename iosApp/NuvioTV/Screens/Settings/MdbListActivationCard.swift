import SwiftUI

/// Shown while an MDBList device authorization awaits approval. Same layout as the Simkl/Trakt
/// activation cards (none of them render a QR code or an expiry countdown, so neither does this
/// one); the shared controller expires the session itself and the section then falls back to the
/// Connect row with a "The code expired" message.
struct MdbListActivationCard: View {
    let code: String
    let verificationUrl: String
    var focusHandOff: Binding<Bool> = .constant(false)
    let onCancel: () -> Void

    var body: some View {
        // Two List rows, not one: as a single row, focusing Cancel lit the whole card with the
        // focus platter and the instructions went white-on-white (device pass 2026-10-17). The
        // text row has nothing focusable, so it never takes the platter.
        Group {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("On your phone or computer, go to")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(verificationUrl)
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("and enter this code:")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(code)
                    .font(Theme.Font.hero.monospaced())
                    .kerning(12)
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.vertical, Theme.Spacing.md)
                HStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    Text("Waiting for approval\u{2026} this screen updates automatically.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            SettingsActionRow(
                title: String(localized: "Cancel"),
                subtitle: String(localized: "Stop waiting and dismiss the code."),
                systemImage: "xmark.circle",
                descriptionID: .servicesActivationCancel
            ) {
                onCancel()
            }
            .claimsFocusAfterSwap(focusHandOff)
        }
    }
}
