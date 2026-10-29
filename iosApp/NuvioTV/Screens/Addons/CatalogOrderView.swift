import SharedCore
import SwiftUI

/// Add-ons hub C, H4: the catalogs page. Switch each Home catalog on or off and set the order of
/// the Home rows, in the shape of the hub's add-on cards. Pushed from the hub's Catalogs card and,
/// per D3, from the Home Screen settings pane's "Catalogs" link row (same page, same model).
///
/// "Match add-ons order" is a ONE-SHOT action, not the "Follow add-ons order" switch the plan
/// sketched: the shared `HomeCatalogSettingsRepository` has no such preference (catalog order is
/// stored per catalog and SYNCED through `HomeCatalogSettingsSyncService`), and a new synced
/// preference needs mobile parity. The action reorders once through `moveByIndex`, collections
/// kept in place, after a confirmation (the order syncs to every device on the profile). A
/// persistent switch stays an open decision for Christian.
///
/// The page lists EVERY Home row in its true order, collections included, each with On/Off and
/// the Up/Down chips (the old Home Screen rows had them). A collection pinned to the top of Home
/// has its chips disabled: the repository re-pins it, so a press would change nothing.
///
/// Identifiers address rows by POSITION (`addons_hub_catalog_<i>`, `_toggle`, `_up`, `_down`);
/// the focus keys (`card:`, `up:`, `down:` plus the catalog key) are internal `@FocusState`
/// values.
struct CatalogOrderView: View {
    @ObservedObject var model: SettingsViewModel

    @FocusState private var focus: String?
    @Namespace private var focusNamespace
    @State private var toast: String?
    @State private var toastSerial = 0
    @State private var confirmingMatch = false

    private var rows: [HomeCatalogSettingsItem] { model.catalogs }

    var body: some View {
        let rows = self.rows
        let orderedKeys = rows.map(\.key)
        let pinnedKeys = Set(rows.filter(\.isPinnedToTop).map(\.key))
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Catalogs")
                    .font(Theme.Font.screenTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .accessibilityIdentifier("addons_hub_catalogs_title")
                Text("Switch each catalog on or off and set the order of your Home rows. Collections appear where Home shows them.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)

                if model.catalogs.isEmpty {
                    Text("No catalogs yet. Install an add-on with catalogs first.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .accessibilityIdentifier("addons_hub_catalogs_empty")
                } else {
                    actionRow
                }

                ForEach(Array(rows.enumerated()), id: \.element.key) { index, item in
                    CatalogRow(
                        item: item,
                        index: index,
                        canMoveUp: Self.canMove(index: index, direction: -1, orderedKeys: orderedKeys, pinnedKeys: pinnedKeys),
                        canMoveDown: Self.canMove(index: index, direction: 1, orderedKeys: orderedKeys, pinnedKeys: pinnedKeys),
                        focus: $focus,
                        onToggle: { model.toggleCatalog(item) },
                        onMoveUp: { move(item, by: -1) },
                        onMoveDown: { move(item, by: 1) }
                    )
                }
            }
            .padding(Theme.Spacing.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .focusScope(focusNamespace)
        .overlay(alignment: .bottom) { toastView }
        .alert("Match add-ons order?", isPresented: $confirmingMatch) {
            Button("Match") {
                let moves = model.matchCatalogsToAddonOrder()
                showToast(moves > 0
                    ? String(localized: "Catalogs now follow your add-ons order.")
                    : String(localized: "Already in add-ons order."))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Home rows will be reordered to follow your add-ons, on every device signed in to this profile.")
        }
        .accessibilityIdentifier("addons_hub_catalogs_root")
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                confirmingMatch = true
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Match add-ons order")
                }
                .font(Theme.Font.body)
                .padding(.horizontal, Theme.Spacing.sm)
            }
            .buttonStyle(.chip)
            .prefersDefaultFocus(true, in: focusNamespace)
            .accessibilityIdentifier("addons_hub_catalogs_match")
            Spacer(minLength: 0)
        }
        .focusSection()
    }

    // MARK: - Reorder

    /// Whether the row at `index` can move one step in `direction` and change what the page shows:
    /// the neighbour must exist and must not be pinned to the top (the repository re-pins pinned
    /// collections), and a pinned row itself never moves.
    nonisolated static func canMove(index: Int, direction: Int, orderedKeys: [String], pinnedKeys: Set<String>) -> Bool {
        guard orderedKeys.indices.contains(index), !pinnedKeys.contains(orderedKeys[index]) else { return false }
        let target = index + direction
        guard orderedKeys.indices.contains(target) else { return false }
        return !pinnedKeys.contains(orderedKeys[target])
    }

    /// The focus key to restore after `key` moved by `direction`, from the list AFTER the move:
    /// the same chip (`up:` / `down:`) while the row can still move further that way, else the
    /// row's name area (`card:`), since a disabled chip cannot hold focus.
    nonisolated static func moveLanding(key: String, direction: Int, orderedKeys: [String], pinnedKeys: Set<String>) -> String {
        guard let index = orderedKeys.firstIndex(of: key),
              canMove(index: index, direction: direction, orderedKeys: orderedKeys, pinnedKeys: pinnedKeys)
        else { return "card:\(key)" }
        return "\(direction < 0 ? "up" : "down"):\(key)"
    }

    /// Moves the row, then puts focus back on the same control of the moved row. The landing is
    /// decided from the item's NEW position, read on the next runloop (the repository's list, else
    /// this model's), not the position the press started from.
    private func move(_ item: HomeCatalogSettingsItem, by delta: Int) {
        let visible = rows
        guard let from = visible.firstIndex(where: { $0.key == item.key }),
              Self.canMove(index: from, direction: delta, orderedKeys: visible.map(\.key),
                           pinnedKeys: Set(visible.filter(\.isPinnedToTop).map(\.key))) else { return }
        if delta < 0 { model.moveUp(item) } else { model.moveDown(item) }
        DispatchQueue.main.async {
            let repoItems = (HomeCatalogSettingsRepository.shared.uiState.value_ as? HomeCatalogSettingsUiState)?.items ?? []
            let list = repoItems.isEmpty ? model.catalogs : repoItems
            focus = Self.moveLanding(
                key: item.key, direction: delta, orderedKeys: list.map(\.key),
                pinnedKeys: Set(list.filter(\.isPinnedToTop).map(\.key))
            )
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Surface.overlay, in: Capsule())
                .padding(.bottom, Theme.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("addons_hub_catalogs_toast")
        }
    }

    private func showToast(_ message: String) {
        toastSerial += 1
        let serial = toastSerial
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastSerial == serial { withAnimation { toast = nil } }
        }
    }
}

/// One catalog: a single focus section like `AddonCardView`. Left/Right stay inside the row (name
/// area, On/Off, Up, Down), Up/Down move between rows.
private struct CatalogRow: View {
    let item: HomeCatalogSettingsItem
    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let focus: FocusState<String?>.Binding
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            nameArea
            Spacer(minLength: Theme.Spacing.md)
            controls
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .focusSection()
    }

    /// The caption: the add-on for a catalog, "Pinned collection" / "Collection" for a collection.
    private var subtitle: String {
        if item.isCollection {
            return item.isPinnedToTop ? String(localized: "Pinned collection") : String(localized: "Collection")
        }
        return item.addonName
    }

    /// Select on the name area toggles, like the old Home Screen row.
    private var nameArea: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.displayTitle)
                    .font(Theme.Font.sectionTitle).rowTextColor().lineLimit(1)
                Text(subtitle)
                    .font(Theme.Font.caption).rowTextColor(secondary: true).lineLimit(1)
                if !item.enabled {
                    DisabledOnHomeLabel()
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.settingsRow)
        .focused(focus, equals: "card:\(item.key)")
        .accessibilityIdentifier("addons_hub_catalog_\(index)")
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(action: onToggle) {
                SettingsSwitchGlyph(isOn: item.enabled)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .buttonStyle(.chip)
            .accessibilityLabel(item.enabled ? Text("On") : Text("Off"))
            .accessibilityValue(item.enabled ? "enabled" : "disabled")
            .accessibilityIdentifier("addons_hub_catalog_\(index)_toggle")

            glyphButton("chevron.up", key: "up", label: "Move up", id: "up", disabled: !canMoveUp, action: onMoveUp)
            glyphButton("chevron.down", key: "down", label: "Move down", id: "down", disabled: !canMoveDown, action: onMoveDown)
        }
    }

    private func glyphButton(
        _ symbol: String, key: String, label: LocalizedStringKey, id: String,
        disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Font.body)
                .padding(.horizontal, Theme.Spacing.sm)
        }
        .buttonStyle(.chip)
        .disabled(disabled)
        .focused(focus, equals: "\(key):\(item.key)")
        .accessibilityLabel(label)
        .accessibilityIdentifier("addons_hub_catalog_\(index)_\(id)")
    }
}

/// "Disabled on Home" in the error tint at rest, joining the platter's dark label colour on focus
/// (an explicit red would stay red-on-white).
private struct DisabledOnHomeLabel: View {
    @Environment(\.settingsRowIsFocused) private var focused

    var body: some View {
        Text("Disabled on Home")
            .font(Theme.Font.caption)
            .foregroundStyle(focused ? Theme.Palette.onFocusPlatter : Theme.Palette.error)
    }
}
