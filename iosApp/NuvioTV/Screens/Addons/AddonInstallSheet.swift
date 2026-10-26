import SwiftUI

/// Add-ons hub C, H2: the install flow, moved verbatim out of the old Add-ons screen into a sheet
/// (H3 polishes it). Today's field, Install button, DEBUG quick-install chip, spinner and status
/// line are unchanged. New: a title, the identifiers the hub's UI legs address, and a self-dismiss
/// 1.2 s after a typed `.installed` outcome (never the localized status text) so the viewer lands back on the list with the new card.
struct AddonInstallSheet: View {
    @ObservedObject var model: AddonsViewModel
    @State private var newUrl = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Install add-on").font(Theme.Font.screenTitle)
            Text("Paste the manifest URL from your streaming addon's config page (e.g. your TorBox or Torrentio URL with your API key). It ends in /manifest.json.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
                .frame(maxWidth: 1200, alignment: .leading)

            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("https://\u{2026}/manifest.json", text: $newUrl)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.screenTitle.weight(.regular))
                    .accessibilityIdentifier("addons_hub_install_field")
            }
            .padding(20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 20) {
                // Not `.disabled` while installing: that disabled the button the user had just
                // pressed and focus jumped away. Guarded in the action instead.
                Button {
                    guard !model.isInstalling else { return }
                    model.install(newUrl)
                    newUrl = ""
                } label: {
                    Label("Install", systemImage: "plus.circle.fill")
                        .padding(.horizontal, 16).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("addons_hub_install_button")

                #if DEBUG
                if DebugConfig.hasManifestURL {
                    Button {
                        guard !model.isInstalling else { return }
                        model.install(DebugConfig.manifestURL)
                    } label: {
                        Label("Quick install (from DebugConfig)", systemImage: "wrench.and.screwdriver")
                            .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                    .buttonStyle(.chip)
                }
                #endif

                if model.isInstalling { ProgressView() }
                if let status = model.statusMessage {
                    Text(status).font(Theme.Font.body).foregroundStyle(.secondary)
                        .accessibilityIdentifier("addons_hub_install_status")
                }
            }
        }
        .padding(Theme.Spacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
        // Cancelled with the sheet (or by a newer outcome), so an early dismissal followed by a
        // reopen never closes the new sheet. H3 refines this; 1.2 s is long enough to read the
        // confirmation.
        .task(id: model.installOutcome) {
            guard case .installed = model.installOutcome else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
