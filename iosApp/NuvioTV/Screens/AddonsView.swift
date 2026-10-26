import SwiftUI
import SharedCore

/// Add-ons hub C, H2: the Sources hub. The body is `SourcesHubView` (summary cards, install and
/// refresh actions, the installed add-on cards). This view keeps what must sit beside the
/// NavigationStack: the stores the hub and its pushed panes read (all six, started and stopped on
/// the stack the way `SettingsView` does, so a push never stops them), the pushed-pane path and
/// the remove confirmation (raised by a card's trash control or the Detail sheet).
struct AddonsView: View {
    @StateObject private var model = AddonsViewModel()
    @StateObject private var settings = SettingsViewModel()
    @StateObject private var debrid = DebridViewModel()
    @StateObject private var plugins = PluginsViewModel()
    @StateObject private var badges = BadgeSettingsViewModel()
    @StateObject private var trakt = TraktViewModel()
    @StateObject private var simkl = SimklViewModel()
    @State private var path: [HubRoute] = []
    /// Addon pending a remove confirmation (drives the alert below).
    @State private var addonPendingRemoval: ManagedAddon?
    /// The neighbours of the card whose removal was requested, so focus can follow the removal.
    /// Owned here so the alert's Cancel can clear it (a later sync removal must not toast or
    /// move focus).
    @State private var removal: SourcesHubView.RemovalIntent?

    var body: some View {
        NavigationStack(path: $path) {
            SourcesHubView(
                model: model, settings: settings, debrid: debrid, plugins: plugins,
                badges: badges, trakt: trakt, simkl: simkl,
                path: $path, pendingRemoval: $addonPendingRemoval, removal: $removal
            )
                // FEAT-30 / H9: Menu summons the rail in Rail mode (a second Menu, with focus in the
                // rail, exits as before). No modifier at all in tabs mode.
                .railMenuReveal()
                // BUG-214: the app background every other screen draws (`SettingsView` does the same
                // on its root). `Theme.Palette.background` is what OLED True Black swaps to pure
                // black; without it OLED never reached this screen.
                .background(Theme.Palette.background.ignoresSafeArea())
                // Sim look (H2 run 2): the stack's large title stays pinned and overlaps the card
                // row once the page scrolls to the add-on cards, so the hub draws its own title
                // inside the content, as the Settings panes do (`settings_pane_title`).
        }
        // On the stack, not the root view: pushing a pane must NOT stop the stores.
        .onAppear {
            model.start()
            settings.start()
            debrid.start()
            plugins.start()
            badges.start()
            trakt.start()
            simkl.start()
        }
        .onDisappear {
            model.stop()
            settings.stop()
            debrid.stop()
            plugins.stop()
            badges.stop()
            trakt.stop()
            simkl.stop()
        }
        .alert(
            "Remove \(addonPendingRemoval.map { model.displayName($0) } ?? "")?",
            isPresented: Binding(
                get: { addonPendingRemoval != nil },
                set: { if !$0 { addonPendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let addon = addonPendingRemoval { model.remove(addon) }
                addonPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                // Review r1: a cancelled removal must not leave its intent behind.
                removal = nil
                addonPendingRemoval = nil
            }
        } message: {
            Text("Its catalogs and streams will no longer appear.")
        }
    }
}
