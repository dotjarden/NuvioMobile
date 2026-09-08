import SwiftUI
import SharedCore

/// Native category rail and detail list. Select commits a category; moving remote focus does
/// not replace the content. The selected category survives theme changes and owns default focus.
/// Native menus handle their own dismissal, and pushed pages keep NavigationStack's Back behavior.
struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @StateObject private var trakt = TraktViewModel()
    @StateObject private var simkl = SimklViewModel()
    @StateObject private var debrid = DebridViewModel()
    @StateObject private var remote = RemoteSetupViewModel()
    @StateObject private var plugins = PluginsViewModel()
    @StateObject private var badges = BadgeSettingsViewModel()
    @EnvironmentObject private var auth: AuthViewModel
    @State private var confirmingSignOut = false
    @State private var confirmingTraktDisconnect = false
    @State private var confirmingSimklDisconnect = false
    /// Provider id pending a debrid disconnect confirmation (drives the alert).
    @State private var debridDisconnectId: String?
    /// "Use the official server?" confirmation (self-hosted → api.nuvio.tv switch-back).
    @State private var confirmingUseOfficial = false
    /// Which category's sections are shown in the detail pane. Non-optional (panes and the pane
    /// switch below read it directly); the `List`'s selection binding adapts it.
    ///
    /// A `@Binding` owned by `ContentView`, NOT local `@State`: `ContentView` pins
    /// `.id(appTheme.themeName)` on the app root, so choosing a theme swatch in the Appearance pane
    /// remounts this whole view. While this was `@State` that remount reset the split to
    /// `.accountServices` — the user pressed a colour and was thrown to the top of Settings with
    /// nothing visibly changed. Same fix, and same reason, as `selectedTab`.
    @Binding var selectedCategory: SettingsCategory
    /// Theme name whose swatch should reclaim focus after a theme-change remount (see
    /// `ContentView.pendingThemeSwatchFocus`); the Appearance pane consumes and clears it.
    @Binding var pendingThemeSwatchFocus: String?
    /// FEAT-30/31: which Appearance row ("navigation" / "typeface") should reclaim focus after a
    /// remount (see `ContentView.pendingAppearanceRowFocus`); the Appearance pane consumes and
    /// clears it, same contract as `pendingThemeSwatchFocus`.
    @Binding var pendingAppearanceRowFocus: String?
    @FocusState private var focusedCategory: SettingsCategory?
    /// Scope that owns the sidebar's default focus — see the focus graph above.
    @Namespace private var sidebarFocus
    /// FEAT-7: "Default" shows the category icon; "Minimal" drops it for a denser sidebar. Set
    /// from the Appearance pane's Settings Style chips.
    @AppStorage("settings_style") private var settingsStyle = "default"

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings").font(Theme.Font.sectionTitle).padding(.horizontal, 20)
                    categorySidebar
                }.frame(width: 400)
                VStack(alignment: .leading, spacing: 20) {
                    Text(selectedCategory.title).accessibilityIdentifier("settingsPaneTitle").font(Theme.Font.sectionTitle).padding(.horizontal, 20)
                    detailPane
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, Theme.Spacing.screen).padding(.top, Theme.Spacing.lg)
            // FEAT-30 (Codex r2, internal review r3 P2-8): in sidebar mode the system tab bar is
            // gone from THIS root too, so Menu / an unplaceable Up at the split root need the same
            // route to the replacement chrome the four scrolling roots have. Attached INSIDE the
            // NavigationStack, on the split itself (like Search/Library/Add-ons attach to their
            // ScrollView): a page pushed by a `SettingsLinkRow` is a descendant of the stack, not
            // of this VStack, so its own Menu (pop) and Up grammar stay untouched.
            .sidebarMenuReveal()
            .background(Theme.Palette.background.ignoresSafeArea())
        }
        .onAppear {
            model.start()
            trakt.start()
            simkl.start()
            debrid.start()
            plugins.start()
            badges.start()
        }
        .onDisappear {
            model.stop()
            trakt.stop()
            simkl.stop()
            debrid.stop()
            plugins.stop()
            badges.stop()
            remote.stop()
        }
        .alert(
            "Apply changes from browser?",
            isPresented: Binding(
                get: { remote.pendingChange != nil },
                set: { if !$0 { remote.rejectPending() } }
            )
        ) {
            Button("Apply") { remote.confirmPending() }
            Button("Decline", role: .cancel) { remote.rejectPending() }
        } message: {
            Text(remote.pendingSummary)
        }
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
            isPresented: Binding(
                get: { debridDisconnectId != nil },
                set: { if !$0 { debridDisconnectId = nil } }
            )
        ) {
            Button("Disconnect", role: .destructive) {
                if let id = debridDisconnectId { debrid.disconnect(id) }
                debridDisconnectId = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes this provider's key from this profile. Streams will no longer resolve through it.")
        }
        .alert(
            auth.isAnonymous ? "Switch to a Nuvio account?" : "Sign out?",
            isPresented: $confirmingSignOut
        ) {
            Button(auth.isAnonymous ? String(localized: "Continue") : String(localized: "Sign Out"), role: .destructive) {
                // Clears the session AND wipes local data (AccountDataCleaner seam), then the root
                // gate drops to the Welcome screen where an account can be signed in.
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                auth.isAnonymous
                    ? "Guest data on this Apple TV (profiles, library, watch progress) will be cleared. You can then sign in on the welcome screen."
                    : "Local data on this Apple TV will be cleared. Your synced data stays in your Nuvio account."
            )
        }
        .alert("Use the official server?", isPresented: $confirmingUseOfficial) {
            Button("Switch", role: .destructive) {
                // Fire-and-forget into the shared controller: clears the session + local data,
                // saves the official config, resets the Supabase client and re-inits auth — the
                // root gate drops to Welcome (which unmounts Settings).
                ServerConnectionController.shared.useOfficial()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You\u{2019}ll be signed out of the self-hosted server and local data on this Apple TV will be cleared. Nuvio will reconnect to api.nuvio.tv.")
        }
    }

    /// Right column: the selected pane's sections inside a native `List`. `settingsUsesNativeList`
    /// tells the shared `settingsSection(_:)` helper it may emit a real `Section` here (it stays
    /// on the legacy stack everywhere else — see SettingsRowViews.swift).
    private var detailPane: some View {
        List {
            pane
        }
        .listStyle(.plain)
        .focusSection()
        .id(selectedCategory)
        .environment(\.settingsUsesNativeList, true)
    }

    /// The detail pane's content for the currently selected sidebar category. Only the selected
    /// category's pane is built (not the others), matching the previous per-section filtering —
    /// keeps focus + perf clean.
    @ViewBuilder
    private var pane: some View {
        switch selectedCategory {
        case .accountServices:
            AccountServicesSettingsPane(
                trakt: trakt,
                simkl: simkl,
                debrid: debrid,
                confirmingSignOut: $confirmingSignOut,
                confirmingTraktDisconnect: $confirmingTraktDisconnect,
                confirmingSimklDisconnect: $confirmingSimklDisconnect,
                debridDisconnectId: $debridDisconnectId,
                confirmingUseOfficial: $confirmingUseOfficial
            )
        case .playback:
            PlaybackSettingsPane(model: model)
        case .appearance:
            AppearanceSettingsPane(
                model: model,
                badges: badges,
                pendingThemeSwatchFocus: $pendingThemeSwatchFocus,
                pendingAppearanceRowFocus: $pendingAppearanceRowFocus
            )
        case .homeScreen:
            HomeScreenSettingsPane(model: model)
        case .contentSources:
            ContentSourcesSettingsPane(model: model, plugins: plugins)
        case .advanced:
            AdvancedSettingsPane(remote: remote)
        case .about:
            AboutSettingsPane()
        }
    }

    /// Left column: one focusable row per category, in a native `List`. Focusing a row
    /// live-selects it (the tvOS Settings pattern); Right enters the pane.
    ///
    /// Rows are `Button`s, not bare `Label`s: a plain `Label` inside `List(selection:)` is NOT
    /// focusable on tvOS (C0 spike finding), so selection alone can't drive the walk. No
    /// `foregroundStyle` here on purpose — the system inverts the row's label colour on the focus
    /// platter, which is what BUG-45's hand-rolled three-way colour switch was working around.
    private var categorySidebar: some View {
        List {
            ForEach(SettingsCategory.allCases) { category in
                Button { selectedCategory = category } label: {
                    HStack(spacing: 18) {
                        if settingsStyle != "minimal" { Image(systemName: category.icon).frame(width: 30).accessibilityHidden(true) }
                        Text(category.title).font(Theme.Font.body)
                        Spacer(minLength: 0)
                        if selectedCategory == category { Image(systemName: "checkmark").font(.caption) }
                    }
                }
                .accessibilityIdentifier("settings.category.\(category.rawValue)")
                .focused($focusedCategory, equals: category)
                .prefersDefaultFocus(category == selectedCategory, in: sidebarFocus)
                .listRowBackground(Color.clear)
            }
        }.listStyle(.plain)
        .focusScope(sidebarFocus).focusSection()
    }
}

/// Settings categories for the split-view sidebar. Order here is the sidebar order.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case accountServices
    case playback
    case appearance
    case homeScreen
    case contentSources
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accountServices: return String(localized: "Account & Services")
        case .playback: return String(localized: "Playback")
        case .appearance: return String(localized: "Appearance")
        case .homeScreen: return String(localized: "Home Screen")
        case .contentSources: return String(localized: "Content Sources")
        case .advanced: return String(localized: "Advanced")
        case .about: return String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .accountServices: return "person.crop.circle"
        case .playback: return "play.rectangle"
        case .appearance: return "paintbrush"
        case .homeScreen: return "house"
        case .contentSources: return "square.stack.3d.up"
        case .advanced: return "gearshape.2"
        case .about: return "info.circle"
        }
    }
}
