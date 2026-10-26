import SharedCore
import SwiftUI

/// Where a summary card pushes. `catalogs` is the catalog order page.
enum HubRoute: Hashable {
    case catalogs, services, plugins
}

/// Add-ons hub C, H2: the Sources hub page body, called by `AddonsView`. A summary row (Add-ons,
/// Catalogs, Debrid, Plugins), an action row (Install, Refresh all, Manage from phone) and the
/// installed add-on cards. `AddonsView` owns every store (started and stopped on the stack) and
/// the remove confirmation; this view observes them. The Services pane's disconnect alerts hang
/// off the pushed pane itself, with their state kept here.
///
/// Plural wording below is deliberately inflection-free ("Repositories: 1 · Providers: 7");
/// H5's catalog pass may add proper plural rules.
struct SourcesHubView: View {
    @ObservedObject var model: AddonsViewModel
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject var debrid: DebridViewModel
    @ObservedObject var plugins: PluginsViewModel
    @ObservedObject var badges: BadgeSettingsViewModel
    @ObservedObject var trakt: TraktViewModel
    @ObservedObject var simkl: SimklViewModel
    @Binding var path: [HubRoute]
    @Binding var pendingRemoval: ManagedAddon?
    @Binding var removal: RemovalIntent?

    @FocusState private var focusedControl: String?
    @Namespace private var focusNamespace
    @State private var showInstall = false
    @State private var detailTarget: DetailTarget?
    /// The add-on whose Remove was pressed in the Detail sheet; promoted to `pendingRemoval` once
    /// the sheet has finished dismissing (an alert cannot present over a sheet).
    @State private var pendingFromSheet: ManagedAddon?
    /// Set when an install succeeds while the sheet is up; the sheet's dismissal then focuses the
    /// new card.
    @State private var focusNewCardAfterInstall = false
    /// Serial of the newest install outcome the hub has seen; handed to the install sheet so a
    /// stale outcome never shows when it reopens.
    @State private var installHandledSerial: Int?
    @State private var toast: String?
    /// Counts toasts shown; the timed clear keys on it, not on the text, so a repeat of the same
    /// text keeps its full time.
    @State private var toastSerial = 0
    // The Services pane's disconnect confirmations, hosted on the pushed pane (SettingsView hosts
    // them for its own copy).
    @State private var confirmingTraktDisconnect = false
    @State private var confirmingSimklDisconnect = false
    @State private var debridDisconnectId: String?

    struct DetailTarget: Identifiable {
        let addon: ManagedAddon
        var id: String { addon.manifestUrl }
    }

    struct RemovalIntent {
        let url: String
        let name: String
        let nextUrl: String?
        let previousUrl: String?
    }

    var body: some View {
        let summary = AddonsViewModel.summary(
            addons: model.addons,
            catalogs: settings.catalogs,
            debridConnectedNames: debrid.providers.filter { debrid.isConnected($0.id) }.map(\.displayName),
            pluginsEnabled: plugins.pluginsEnabled,
            pluginRepositories: plugins.repositories.count,
            pluginProviders: plugins.scrapers.count
        )
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sectionGap) {
                    Text("Add-ons")
                        .font(Theme.Font.screenTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .accessibilityIdentifier("addons_hub_title")
                    summaryRow(summary, proxy: proxy)
                    actionRow
                    installedSection
                }
                .padding(Theme.Spacing.screen)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Entry focus: Down from the tab bar lands on the Add-ons summary card.
            .focusScope(focusNamespace)
            .reportsScrollToTabBar(tab: "Add-ons")
            .accessibilityIdentifier("addons_hub_root")
        }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showInstall, onDismiss: focusAfterInstall) { AddonInstallSheet(model: model, handledSerial: installHandledSerial) }
        .sheet(item: $detailTarget, onDismiss: {
            // The sheet is gone: now the confirm alert can present.
            if let addon = pendingFromSheet {
                pendingFromSheet = nil
                pendingRemoval = addon
            }
        }) { target in
            AddonDetailSheet(model: model, snapshot: target.addon, isReadOnly: model.isReadOnly) {
                requestRemoval(target.addon, fromSheet: true)
            }
        }
        .navigationDestination(for: HubRoute.self) { route in destination(route) }
        .onChange(of: model.refreshOutcomeSerial) { _, _ in
            guard let outcome = model.lastRefreshOutcome else { return }
            showToast(outcome.failed == 0
                ? String(localized: "Refreshed \(outcome.succeeded).")
                : String(localized: "Refreshed \(outcome.succeeded), \(outcome.failed) failed."))
        }
        .onChange(of: model.installOutcome) { _, outcome in
            guard let outcome else { return }
            installHandledSerial = AddonInstallSheet.serial(of: outcome)
            // The install sheet's status modal says it, so no toast while it is up.
            if showInstall {
                if case .installed = outcome { focusNewCardAfterInstall = true }
                return
            }
            switch outcome {
            case .installed(let name, _):
                showToast(String(localized: "Installed \(name)."))
                // The sheet was closed mid-install (Menu): it will not run `focusAfterInstall`.
                focusNewestCard()
            // Fixed text only: the detailed message can embed the full manifest URL (with a
            // debrid key), so it stays in the install sheet's status modal.
            case .failed: showToast(String(localized: "Couldn't install that add-on."))
            }
        }
        .onChange(of: model.addons.map(\.manifestUrl)) { _, urls in handleRemoval(urls) }
    }

    // MARK: - Summary row

    private func summaryRow(_ summary: AddonsViewModel.HubSummary, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            HubCard(
                title: String(localized: "Add-ons"),
                value: Text(String(localized: "\(summary.addonsInstalled) installed · \(summary.addonsOn) on")),
                loading: !model.isInitialized,
                id: "addons_hub_summary_addons",
                defaultFocusScope: focusNamespace
            ) {
                proxy.scrollTo("addons_hub_installed", anchor: .top)
                guard let first = model.addons.first else { return }
                DispatchQueue.main.async { focusedControl = "card:" + first.manifestUrl }
            } accessory: {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(AddonsViewModel.logoUrls(of: model.addons, limit: 5).enumerated()), id: \.offset) { _, url in
                        CachedAsyncImage(string: url)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    }
                }
            }
            HubCard(
                title: String(localized: "Catalogs"),
                value: Text(String(localized: "\(summary.catalogsOn) of \(summary.catalogsTotal) on Home")),
                id: "addons_hub_summary_catalogs"
            ) {
                path.append(.catalogs)
            }
            HubCard(
                title: String(localized: "Debrid"),
                value: Text(summary.debridConnected.isEmpty
                    ? String(localized: "Not connected")
                    : String(localized: "\(summary.debridConnected.joined(separator: ", ")) connected")),
                id: "addons_hub_summary_debrid"
            ) {
                path.append(.services)
            }
            if let plugin = summary.plugins {
                HubCard(
                    title: String(localized: "Plugins"),
                    value: Text(String(localized: "Repositories: \(plugin.repositories) · Providers: \(plugin.providers)")),
                    id: "addons_hub_summary_plugins"
                ) {
                    path.append(.plugins)
                }
            }
        }
        .focusSection()
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.lg) {
            HubCard(
                title: String(localized: "Install add-on"),
                value: Text("From a manifest URL"),
                systemImage: "plus.circle.fill",
                id: "addons_hub_action_install"
            ) {
                showInstall = true
            }
            .focused($focusedControl, equals: "action:install")

            HubCard(
                title: String(localized: "Refresh all"),
                value: refreshSubtitle,
                systemImage: "arrow.clockwise",
                loading: model.isRefreshingAny,
                id: "addons_hub_action_refresh"
            ) {
                let enabled = model.addons.filter { $0.enabled }.count
                showToast(enabled == 0
                    ? String(localized: "Nothing to refresh.")
                    : String(localized: "Refreshing add-ons (\(enabled))…"))
                model.refreshAll()
            }

            if DebugConfig.showsPhoneManagement {
                HubCard(
                    title: String(localized: "Manage from phone"),
                    value: Text("Coming in a later beta"),
                    systemImage: "iphone",
                    id: "addons_hub_action_phone"
                ) {}
            }
        }
        .focusSection()
    }

    /// "Updated <relative>" as a live `Text`: the relative style ticks by itself, and nothing is
    /// allocated per render.
    private var refreshSubtitle: Text {
        guard let stamp = model.lastRefreshedAt else { return Text("Not refreshed yet") }
        return Text("Updated \(stamp, style: .relative)")
    }

    // MARK: - Installed section

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Installed add-ons").font(Theme.Font.screenTitle)
                    .accessibilityIdentifier("addons_hub_installed_title")
                if !model.isInitialized { ProgressView() }
            }
            if model.isInitialized && model.addons.isEmpty {
                Text("No add-ons installed. Install one to get started.")
                    .font(Theme.Font.body).foregroundStyle(Theme.Palette.textSecondary)
                    .accessibilityIdentifier("addons_hub_empty")
            }
            if model.isReadOnly {
                Text("This profile uses the primary profile's add-ons. Manage them there.")
                    .font(Theme.Font.body).foregroundStyle(Theme.Palette.textSecondary)
                    .accessibilityIdentifier("addons_hub_readonly")
            }
            ForEach(Array(model.addons.enumerated()), id: \.element.manifestUrl) { index, addon in
                AddonCardView(
                    addon: addon,
                    index: index,
                    count: model.addons.count,
                    isReadOnly: model.isReadOnly,
                    focus: $focusedControl,
                    onOpen: { detailTarget = DetailTarget(addon: addon) },
                    onToggle: { model.setEnabled(addon, !addon.enabled) },
                    onMoveUp: { move(addon, index: index, by: -1) },
                    onMoveDown: { move(addon, index: index, by: 1) },
                    onRemove: { requestRemoval(addon, fromSheet: false) }
                )
            }
        }
        .id("addons_hub_installed")
    }

    // MARK: - Reorder and removal

    /// Moves the card, then puts focus back on the same control of the moved card. A move that
    /// lands at an end disables that control, so focus goes to the card's name area instead. The
    /// landing is decided from the add-on's NEW index (the repository's list, else this model's),
    /// not the render index the press started from.
    private func move(_ addon: ManagedAddon, index: Int, by delta: Int) {
        let count = model.addons.count
        guard AddonsViewModel.moveTarget(index: index, by: delta, count: count) != nil else { return }
        model.move(manifestUrl: addon.manifestUrl, by: delta)
        DispatchQueue.main.async {
            let repoList = (AddonRepository.shared.uiState.value_ as? AddonsUiState)?.addons ?? []
            let list = repoList.isEmpty ? model.addons : repoList
            let newIndex = list.firstIndex { $0.manifestUrl == addon.manifestUrl } ?? (index + delta)
            let atEnd = delta < 0 ? newIndex <= 0 : newIndex >= list.count - 1
            let key = atEnd ? "card" : (delta < 0 ? "up" : "down")
            focusedControl = "\(key):\(addon.manifestUrl)"
        }
    }

    /// Raises the shared confirm alert (owned by `AddonsView`). From the Detail sheet the sheet
    /// closes first and the sheet's `onDismiss` promotes the stash: an alert cannot present over
    /// a sheet.
    private func requestRemoval(_ addon: ManagedAddon, fromSheet: Bool) {
        let urls = model.addons.map(\.manifestUrl)
        let at = urls.firstIndex(of: addon.manifestUrl)
        removal = RemovalIntent(
            url: addon.manifestUrl,
            name: AddonsViewModel.displayTitle(addon),
            nextUrl: at.flatMap { $0 + 1 < urls.count ? urls[$0 + 1] : nil },
            previousUrl: at.flatMap { $0 > 0 ? urls[$0 - 1] : nil }
        )
        if fromSheet {
            pendingFromSheet = addon
            detailTarget = nil
        } else {
            pendingRemoval = addon
        }
    }

    /// Once a requested removal has left the list: toast it, and focus the card that took its
    /// place (the previous one at the end, the Install card when the list is empty).
    private func handleRemoval(_ urls: [String]) {
        guard let intent = removal, !urls.contains(intent.url) else { return }
        removal = nil
        showToast(String(localized: "Removed \(intent.name)."))
        let target = [intent.nextUrl, intent.previousUrl].compactMap { $0 }.first(where: urls.contains)
        DispatchQueue.main.async { focusedControl = target.map { "card:" + $0 } ?? "action:install" }
    }

    /// After the install sheet closes following a successful install: focus the card of the add-on
    /// that was installed, else the last card, else the Install action card.
    private func focusAfterInstall() {
        guard focusNewCardAfterInstall else { return }
        focusNewCardAfterInstall = false
        focusNewestCard()
    }

    private func focusNewestCard() {
        DispatchQueue.main.async {
            let installed = model.lastInstalledManifestUrl.flatMap { url in
                model.addons.first { AddonManifestURL.isSameManifest($0.manifestUrl, url) }
            }
            focusedControl = (installed ?? model.addons.last).map { "card:" + $0.manifestUrl } ?? "action:install"
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: HubRoute) -> some View {
        switch route {
        case .catalogs:
            CatalogOrderView(model: settings)
        case .services:
            SettingsPaneScaffold(category: .services) {
                ServicesSettingsPane(
                    trakt: trakt,
                    simkl: simkl,
                    debrid: debrid,
                    confirmingTraktDisconnect: $confirmingTraktDisconnect,
                    confirmingSimklDisconnect: $confirmingSimklDisconnect,
                    debridDisconnectId: $debridDisconnectId
                )
            }
            // On the pushed pane, not the stack root: a covered root's presentation can be dropped,
            // which would leave Disconnect dead. Same actions as `SettingsView`.
            .alert("Disconnect Trakt?", isPresented: $confirmingTraktDisconnect) {
                Button("Disconnect", role: .destructive) { trakt.disconnect() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Scrobbling stops and this Apple TV's Trakt access token is revoked. Your Trakt history is untouched.")
            }
            .alert("Disconnect Simkl?", isPresented: $confirmingSimklDisconnect) {
                Button("Disconnect", role: .destructive) { simkl.disconnect() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Scrobbling stops and this Apple TV's Simkl authorization is cleared. Your Simkl history is untouched.")
            }
            .alert(
                "Disconnect debrid provider?",
                isPresented: Binding(get: { debridDisconnectId != nil }, set: { if !$0 { debridDisconnectId = nil } })
            ) {
                Button("Disconnect", role: .destructive) {
                    if let id = debridDisconnectId { debrid.disconnect(id) }
                    debridDisconnectId = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes this provider's key from this profile. Streams will no longer resolve through it.")
            }
        case .plugins:
            SettingsPaneScaffold(category: .sources) {
                SourcesSettingsPane(model: settings, plugins: plugins, badges: badges)
            }
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
                .accessibilityIdentifier("addons_hub_toast")
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

/// A summary or action card: title, value line and an optional accessory (the logo strip), on the
/// kit's `.settingsRow` platter (white on focus, text through `rowTextColor`). `loading` swaps a
/// spinner in for the accessory (or, with no accessory, shows it beside the title). `value` is a
/// `Text` so a card can carry a live relative date.
private struct HubCard<Accessory: View>: View {
    let title: String
    let value: Text
    var systemImage: String?
    var loading = false
    let id: String
    var defaultFocusScope: Namespace.ID?
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    /// Stand-in scope for `prefersDefaultFocus` when this card is not the page's default.
    @Namespace private var fallbackNamespace

    init(
        title: String, value: Text, systemImage: String? = nil, loading: Bool = false, id: String,
        defaultFocusScope: Namespace.ID? = nil,
        action: @escaping () -> Void, @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.loading = loading
        self.id = id
        self.defaultFocusScope = defaultFocusScope
        self.action = action
        self.accessory = accessory
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    if let systemImage { Image(systemName: systemImage).font(Theme.Font.cardTitle) }
                    Text(title).font(Theme.Font.cardTitle)
                    if loading && Accessory.self == EmptyView.self { ProgressView().controlSize(.small) }
                }
                .rowTextColor(secondary: true)
                value.font(Theme.Font.sectionTitle).lineLimit(2).rowTextColor()
                if loading && Accessory.self != EmptyView.self {
                    ProgressView()
                } else {
                    accessory()
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            // Sim look (H2 run 1): with the platter-free row style the unfocused cards read as
            // loose text columns; a `surface` card at rest keeps the plan's "summary cards".
            .background(HubCardSurface())
        }
        .buttonStyle(.settingsRow)
        .prefersDefaultFocus(defaultFocusScope != nil, in: defaultFocusScope ?? fallbackNamespace)
        .accessibilityIdentifier(id)
    }
}

/// The card's resting fill. A child of the button's LABEL on purpose: the row style publishes
/// `settingsRowIsFocused` into the label's environment only, so a read on the card itself would
/// always be false and the fill would sit on the white platter. Clear while focused.
private struct HubCardSurface: View {
    @Environment(\.settingsRowIsFocused) private var rowFocused

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(rowFocused ? Color.clear : Theme.Palette.surface)
    }
}

extension HubCard where Accessory == EmptyView {
    fileprivate init(
        title: String, value: Text, systemImage: String? = nil, loading: Bool = false, id: String,
        defaultFocusScope: Namespace.ID? = nil,
        action: @escaping () -> Void
    ) {
        self.init(title: title, value: value, systemImage: systemImage, loading: loading, id: id,
                  defaultFocusScope: defaultFocusScope, action: action, accessory: { EmptyView() })
    }
}
