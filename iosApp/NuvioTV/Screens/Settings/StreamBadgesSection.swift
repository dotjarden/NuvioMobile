import SwiftUI
import SharedCore

/// The Stream Badges section body (Appearance category): toggles + placement + imported
/// badge-pack management, all backed by the shared `StreamBadgeSettingsRepository` (syncs across
/// devices). Extracted from SettingsView.swift (Phase 2 HIG revamp file split) — logic and wiring
/// preserved verbatim.
///
/// beta.15 §C (C3a): the three toggles bind straight to the view-model instead of the legacy
/// value+action shim. The per-pack row (name/filter-count + Active-or-"Set Active" + delete) and
/// `BadgeUrlEntryRow` stay custom compositions — no kit primitive covers a row with two
/// independent trailing actions, or a URL importer with an async progress state — see the C3a
/// report for the full rationale.
struct StreamBadgesSection: View {
    @ObservedObject var badges: BadgeSettingsViewModel

    var body: some View {
        Text("Add quality, HDR and audio labels to stream results. Imported packs sync with Nuvio.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: 1100, alignment: .leading)

        SettingsToggleRow(
            title: String(localized: "File Size Badges"),
            subtitle: String(localized: "Show the video size (GB/MB) as a chip on stream results."),
            isOn: Binding(get: { badges.showFileSizeBadges }, set: { badges.setShowFileSizeBadges($0) })
        )
        SettingsToggleRow(
            title: String(localized: "Show Add-on Logo"),
            subtitle: String(localized: "Show each result's add-on logo and name on the right of the row."),
            isOn: Binding(get: { badges.showAddonLogo }, set: { badges.setShowAddonLogo($0) })
        )
        SettingsToggleRow(
            title: String(localized: "Badges Above Title"),
            subtitle: badges.badgesOnTop
                ? String(localized: "Badge chips render above the stream name.")
                : String(localized: "Badge chips render below the stream description."),
            isOn: Binding(get: { badges.badgesOnTop }, set: { badges.setBadgesOnTop($0) })
        )

        if badges.imports.isEmpty {
            Text("No badge packs imported yet.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        } else {
            ForEach(badges.imports, id: \.sourceUrl) { pack in
                Menu {
                    Button("Set Active") { badges.setActive(pack.sourceUrl) }
                        .disabled(pack.isActive)
                    Button("Remove Pack", role: .destructive) { badges.deletePack(pack.sourceUrl) }
                } label: {
                    LabeledContent {
                        Text(pack.isActive ? String(localized: "Active") : String(localized: "Inactive"))
                            .foregroundStyle(.secondary)
                    } label: {
                        SettingsRowLabel(title: BadgeSettingsViewModel.packLabel(pack.sourceUrl),
                                         subtitle: String(localized: "\(pack.enabledFilterCount) filters"))
                    }
                }
            }
        }

        BadgeUrlEntryRow(isImporting: badges.isImporting) { badges.importPack(url: $0) }

        if let status = badges.statusMessage {
            Text(status)
                .font(Theme.Font.caption)
                .foregroundStyle(badges.importSucceeded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
    }
}

/// URL entry + import button for a stream badge pack (mirrors `PluginRepoEntryRow`).
private struct BadgeUrlEntryRow: View {
    let isImporting: Bool
    let onImport: (String) -> Void
    @State private var url = ""

    var body: some View {
        SettingsTextEntryRow(placeholder: String(localized: "Badge pack JSON URL"),
                             buttonTitle: String(localized: "Import"), text: $url, busy: isImporting) {
            onImport(url)
        }
    }
}
