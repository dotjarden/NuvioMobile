import SwiftUI
import SharedCore

/// The Stream Badges section body (Appearance category): toggles + placement + imported
/// badge-pack management, all backed by the shared `StreamBadgeSettingsRepository` (syncs across
/// devices). Extracted from SettingsView.swift (Phase 2 HIG revamp file split) — logic and wiring
/// preserved verbatim.
///
/// beta.15 §C (C3a): the three toggles bind straight to the view-model instead of the legacy
/// value+action shim.
///
/// BUG-213 (GitHub #10): the per-pack row (name/filter-count + Active-or-"Set Active" + delete)
/// and `BadgeUrlEntryRow` used to be one List row each holding two controls, and a tvOS List row
/// is one focus target (the BUG-197 diagnosis), so the controls highlighted as one block. Each is
/// now two List rows built from the settings kit: a pack row that sets the pack active and a
/// separate Delete row; a URL field row and a separate Import row.
struct StreamBadgesSection: View {
    @ObservedObject var badges: BadgeSettingsViewModel

    var body: some View {
        Text("Badge packs add quality / HDR / audio-channel chips to stream results. Import a pack by its JSON URL \u{2014} packs imported on the Nuvio mobile app sync here automatically. Tip: Remote Setup (Account & Profiles) lets you paste the URL from a phone browser.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: 1100, alignment: .leading)

        SettingsToggleRow(
            title: String(localized: "File Size Badges"),
            subtitle: String(localized: "Show the video size (GB/MB) as a chip on stream results."),
            isOn: Binding(get: { badges.showFileSizeBadges }, set: { badges.setShowFileSizeBadges($0) }),
            descriptionID: .appearanceBadgesFileSize
        )
        SettingsToggleRow(
            title: String(localized: "Show Add-on Logo"),
            subtitle: String(localized: "Show each result's add-on logo and name on the right of the row."),
            isOn: Binding(get: { badges.showAddonLogo }, set: { badges.setShowAddonLogo($0) }),
            descriptionID: .appearanceBadgesAddonLogo
        )
        SettingsToggleRow(
            title: String(localized: "Badges Above Title"),
            subtitle: badges.badgesOnTop
                ? String(localized: "Badge chips render above the stream name.")
                : String(localized: "Badge chips render below the stream description."),
            isOn: Binding(get: { badges.badgesOnTop }, set: { badges.setBadgesOnTop($0) }),
            descriptionID: .appearanceBadgesAboveTitle
        )

        if badges.imports.isEmpty {
            Text("No badge packs imported yet.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        } else {
            ForEach(badges.imports, id: \.sourceUrl) { pack in
                // Two List rows per pack, not one: the Set Active button and the Delete button
                // used to share a row, which the tvOS List treats as ONE focus target.
                Button {
                    // The active pack already is what a press would set; nothing to do.
                    if !pack.isActive { badges.setActive(pack.sourceUrl) }
                } label: {
                    SettingsRowChrome {
                        SettingsRowLabel(
                            title: BadgeSettingsViewModel.packLabel(pack.sourceUrl),
                            subtitle: pack.enabledFilterCount == 1 ? String(localized: "1 filter \u{00B7} \(pack.sourceUrl)") : String(localized: "\(pack.enabledFilterCount) filters \u{00B7} \(pack.sourceUrl)"),
                            systemImage: pack.isActive ? "checkmark.circle.fill" : "checkmark.circle",
                            descriptionID: .appearanceBadgePack
                        )
                        .lineLimit(1)
                    } trailing: {
                        SettingsTrailingValue(
                            value: pack.isActive ? String(localized: "Active") : String(localized: "Set Active"),
                            showsChevron: false
                        )
                    }
                }
                SettingsDestructiveRow(
                    title: String(localized: "Delete Badge Pack"),
                    systemImage: "trash",
                    descriptionID: .appearanceBadgePack
                ) {
                    badges.deletePack(pack.sourceUrl)
                }
            }
        }

        BadgeUrlEntryRow(isImporting: badges.isImporting) { badges.importPack(url: $0) }

        if let status = badges.statusMessage {
            Text(status)
                .font(Theme.Font.caption)
                .foregroundStyle(status.hasPrefix("Imported") ? Theme.Palette.textSecondary : .red)
        }
    }
}

/// URL entry + import button for a stream badge pack (mirrors `PluginRepoEntryRow`). BUG-213: the
/// `Group` body yields TWO List rows, the URL field row (rest platter follows the field's
/// `@FocusState`, a `TextField` has no label to read `\.isFocused` from) and an Import kit row,
/// so each is its own focus target. `@State url` stays owned by this struct. No in-content glass
/// (HIG hybrid contract: glass is floating chrome).
private struct BadgeUrlEntryRow: View {
    let isImporting: Bool
    let onImport: (String) -> Void
    @State private var url = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "tag")
                    .font(SettingsRowFont.title)
                    .foregroundStyle(.secondary)
                TextField("Badge pack JSON URL", text: $url)
                    .textFieldStyle(.plain)
                    .font(SettingsRowFont.title)
                    .focused($fieldFocused)
            }
            .modifier(SettingsRestPlatter(explicitFocus: fieldFocused))
            .settingsDescription(.appearanceBadgeImport, title: String(localized: "Badge pack JSON URL"), systemImage: "tag", focused: fieldFocused)

            // Not `.disabled(isImporting)`: the pressed button lost focus. Guarded in the action,
            // and the label stays the same row while importing (the spinner rides in `trailing`).
            Button {
                if !url.isEmpty, !isImporting {
                    onImport(url)
                    url = ""
                }
            } label: {
                SettingsRowChrome {
                    SettingsRowLabel(
                        title: String(localized: "Import Badge Pack"),
                        systemImage: "plus",
                        descriptionID: .appearanceBadgeImport
                    )
                } trailing: {
                    if isImporting {
                        ProgressView().scaleEffect(0.6)
                    }
                }
            }
        }
    }
}
