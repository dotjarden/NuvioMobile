import Foundation
import SwiftUI
import SharedCore

/// "Account & Profiles" category rows (detail-settings-revamp W2-B): Sign In / Sign Out, the
/// Server section and Remote Setup, moved out of the old Account & Services and Advanced panes.
/// Rows only: `SettingsPaneScaffold` supplies the `List`. Logic and wiring preserved verbatim.
struct AccountProfilesSettingsPane: View {
    @ObservedObject var remote: RemoteSetupViewModel
    /// Set by Start / Stop Remote Setup right before the row swaps for the other one, so the
    /// replacement takes focus (see `claimsFocusAfterSwap`).
    @State private var remoteFocusHandOff = false
    @EnvironmentObject private var auth: AuthViewModel
    /// Active backend (official vs self-hosted) for the Server section.
    @StateObject private var server = ActiveServerObserver()
    /// FEAT-65: "Open Last Profile at Launch" (the shared `rememberLastProfileEnabled` flag).
    @StateObject private var lastProfile = RememberLastProfileModel()

    /// Drives the shared sign-in/sign-out confirmation alert owned by SettingsView.
    @Binding var confirmingSignOut: Bool
    /// Drives the shared "Use the official server?" confirmation alert owned by SettingsView.
    @Binding var confirmingUseOfficial: Bool

    var body: some View {
        Group {
            SettingsSection(String(localized: "Account")) {
                if auth.isAnonymous {
                    SettingsActionRow(
                        title: String(localized: "Sign In to Nuvio"),
                        subtitle: String(localized: "Sync your library, watch progress, and profiles across devices. Local guest data on this Apple TV will be cleared."),
                        systemImage: "person.crop.circle.badge.plus",
                        descriptionID: .accountSignInOut
                    ) {
                        confirmingSignOut = true
                    }
                } else {
                    SettingsDestructiveRow(
                        title: String(localized: "Sign Out"),
                        subtitle: String(localized: "Signed in as \(auth.accountEmail ?? "your Nuvio account"). Local data on this Apple TV will be cleared."),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        descriptionID: .accountSignInOut
                    ) {
                        confirmingSignOut = true
                    }
                }
            }

            // FEAT-65 (Steven, beta.19-rc3 follow-up 2026-10-08: open straight into his profile).
            // Off by default; a PIN profile still shows the picker. The decision is
            // `ProfileAutoEnter`, applied once per cold launch by `ContentView`.
            SettingsSection(String(localized: "Profiles")) {
                SettingsToggleRow(
                    title: String(localized: "Open Last Profile at Launch"),
                    subtitle: String(localized: "Skips the profile picker and opens the profile you used last. Profiles with a PIN still ask for it. Default: Off."),
                    isOn: Binding(get: { lastProfile.enabled }, set: { lastProfile.set($0) }),
                    descriptionID: .accountRememberLastProfile
                )
                .accessibilityIdentifier("account_row_remember_last_profile")
            }

            SettingsSection(String(localized: "Server")) {
                serverSection
            }

            SettingsSection(String(localized: "Remote Setup")) {
                remoteSetupSection
            }
        }
        .onAppear { lastProfile.start() }
    }

    /// The Server section: which backend this Apple TV talks to, plus the self-hosted discovery
    /// entry point and (when on a custom server) the way back to api.nuvio.tv. Both switches are
    /// destructive (sign-out + local wipe) — the "Use Official Server" confirm is a `.alert` on
    /// SettingsView; the connect flow confirms inside `ServerConnectionView`.
    @ViewBuilder
    private var serverSection: some View {
        SettingsValueRow(
            title: String(localized: "Server"),
            value: server.isCustom
                ? server.displayHost
                : String(localized: "Official Nuvio (\(server.displayHost))"),
            systemImage: "server.rack"
        )
        SettingsLinkRow(
            title: server.isCustom
                ? String(localized: "Connect to Another Server")
                : String(localized: "Connect to a Self-Hosted Server"),
            subtitle: String(localized: "Point this Apple TV at a self-hosted Nuvio backend. Switching servers signs you out and clears local data on this Apple TV."),
            systemImage: "network",
            descriptionID: .accountConnectServer
        ) {
            ServerConnectionView()
        }
        if server.isCustom {
            SettingsDestructiveRow(
                title: String(localized: "Use Official Server"),
                subtitle: String(localized: "Switch back to api.nuvio.tv. You\u{2019}ll be signed out and local data on this Apple TV will be cleared."),
                systemImage: "arrow.uturn.backward",
                descriptionID: .accountUseOfficialServer
            ) {
                confirmingUseOfficial = true
            }
        }
    }

    /// The Remote Setup section body: start/stop the LAN config server and, while it runs, show
    /// the URL + QR a phone/laptop browser uses to manage add-ons, Home rows, API keys, and
    /// badge packs. Changes proposed from the browser surface as a confirm alert on SettingsView.
    @ViewBuilder
    private var remoteSetupSection: some View {
        Text("Manage add-ons, Home rows, API keys, and stream badge packs from a phone or laptop browser on the same network \u{2014} no on-screen keyboard. Changes only apply after you confirm them here.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: 1100, alignment: .leading)

        if let url = remote.serverURL {
            // Stop sits where Start was, ABOVE the QR block: it replaces Start in place, so focus
            // can hand over. Below the QR it was off screen, and the lazy List never built the row
            // to take focus (device pass 2026-10-17: focus fell to the Server row above).
            SettingsActionRow(
                title: String(localized: "Stop Remote Setup"),
                subtitle: String(localized: "Closes the local config page."),
                systemImage: "stop.circle",
                descriptionID: .accountRemoteSetup
            ) {
                remoteFocusHandOff = true
                remote.stop()
            }
            .claimsFocusAfterSwap($remoteFocusHandOff)
            HStack(alignment: .top, spacing: 40) {
                if let qr = remote.qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scan the code, or open in any browser:")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text(url)
                        .font(Theme.Font.screenTitle.monospaced())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Keep this Settings screen open while you make changes.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        } else {
            SettingsActionRow(
                title: String(localized: "Start Remote Setup"),
                subtitle: remote.startFailed
                    ? String(localized: "Couldn't start the local server. Check the network connection and try again.")
                    : String(localized: "Starts a local config page on your network."),
                systemImage: "network",
                descriptionID: .accountRemoteSetup
            ) {
                remoteFocusHandOff = true
                remote.start()
            }
            .claimsFocusAfterSwap($remoteFocusHandOff)
            // A failed start never swaps the row; don't leave the hand-off armed (review r1 P3).
            .onChange(of: remote.startFailed) { _, failed in
                if failed { remoteFocusHandOff = false }
            }
        }
    }
}
