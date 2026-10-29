//
//  NuvioTVApp.swift
//  NuvioTV
//
//  Created by Christian Turnbull on 6/29/26.
//

import AVFAudio
import CoreText
import SwiftUI
import SharedCore
import UIKit

/// FEAT-31: registers the bundled Open Sans faces with CoreText (idempotent — skips work if the
/// face is already available, e.g. a second `NuvioTVApp` init in a test host) and applies the
/// persisted `ui_font` choice to `Theme.Font`. The Settings row that writes that key is a separate
/// wave's work; this is just the launch-time wiring.
enum AppFontRegistrar {
    private static let filenames = ["OpenSans-Regular.ttf", "OpenSans-SemiBold.ttf", "OpenSans-Bold.ttf"]

    /// Call once, before any view is built.
    static func registerIfNeeded() {
        if UIFont(name: "OpenSans-Regular", size: 12) == nil {
            for filename in filenames {
                guard let url = fontURL(for: filename) else {
                    NSLog("[AppFontRegistrar] missing bundled font resource: \(filename)")
                    continue
                }
                var error: Unmanaged<CFError>?
                if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    NSLog("[AppFontRegistrar] failed to register \(filename): \(String(describing: error))")
                }
            }
        }
        Theme.Font.apply(Theme.AppFontFamily.fromDefaults())
    }

    /// The project's fully file-system-synchronized target can flatten a synced subfolder into the
    /// bundle root depending on how Xcode stages it, so try no subdirectory first, then the two
    /// folder names `Resources/Fonts/` might keep in the built bundle.
    private static func fontURL(for filename: String) -> URL? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Fonts")
    }
}

@main
struct NuvioTVApp: App {
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--live-tv-ui-test") {
            // Isolated test profile; never installed in release builds or normal launches.
            let source = LiveTVSource(name: "Local test provider", kind: .m3u, address: "http://127.0.0.1:8766/playlist.m3u")
            try? LiveTVSecureStorage.write([source], profile: "live-tv-ui-test")
        }
        if ProcessInfo.processInfo.arguments.contains("--live-player-ui-test") {
            let source = LiveTVSource(name: "Player focus fixture", kind: .m3u, address: "http://127.0.0.1:8767/playlist.m3u")
            try? LiveTVSecureStorage.write([source], profile: "live-player-ui-test")
        }
        LaunchTrace.mark("app_init")  // BUG-26: cold-start attribution zero point
        #endif
        _ = HomeHeroProbe.t0  // BUG-42: anchor the release-safe hero probe's clock at process init
        _ = NetworkPathMonitor.shared  // P4 BUG-143: start the path monitor so the first failure reads a real value
        // I1 (beta.19-rc1 verdict, BUG-134): seed the display scale non-view artwork code decodes with
        // (hero resolver, prefetch) while we are certainly on the main thread.
        ArtworkDecodeMath.seedScreenScale()

        // FEAT-31: register the bundled Open Sans faces + apply the persisted font choice before
        // any view (and therefore any `Theme.Font.*` read) is built.
        AppFontRegistrar.registerIfNeeded()

        // Wire the shared provider seams for tvOS (profiles, sync platform "tv", account-data
        // cleaner, sync-backend load). The phone app does this in composeApp's App() (which tvOS
        // never runs). Runs once, before any repository is accessed.
        TvOsProviderInstallerKt.installTvOsSharedProviders()

        // ui-legs (2026-10-22): `-debug.tmdbEnabledOverride YES|NO` (DEBUG only) sets TMDB
        // enrichment for this launch, in memory, never written or synced. Before any repository load.
        TmdbDebugOverride.apply()
        // harness-w4 (2026-10-23): the same seam for two more synced keys the UI legs need, DEBUG
        // only, in memory, never written or synced: `-debug.streamAutoPlayModeOverride <MODE>`
        // (stream_auto_play_mode) and `-debug.amoledEnabledOverride YES|NO` (amoled_enabled).
        StreamAutoPlayModeDebugOverride.apply()
        AmoledDebugOverride.apply()

        // Native (AVPlayer) engine is ON by default since beta.13 (info-panel work; see
        // docs/tvos-native-player-info-panel-plan.md). Registered — not written — so a user's explicit
        // OFF survives, and every `bool(forKey:)` reader (PlayerScreen routing, SettingsViewModel)
        // sees the same default without its own fallback logic.
        UserDefaults.standard.register(defaults: [PlayerTuning.nativeDVKey: true, "hero_nuvio_style": true])

        // beta.19-rc1 verdict (F, FEAT-54): the BUG-118 Developer A/B `debug.rowEdgeFade` became the
        // Appearance setting `row_edge_fade` (Off by default). An explicit old Soft, Automatic or Off
        // carries across (`legacySetting`), Hard does not; the legacy key is removed, and an existing
        // `row_edge_fade` is never overwritten. Before any row reads the setting.
        RowEdgeFadeSetting.migrateLegacy(UserDefaults.standard)

        // Home Stage & Strip (H9, P4 R6): FEAT-30's stored `sidebar_style = "sidebar"` becomes
        // `"rail"`, once and device-local. Reads the persistent domain only, so a `-sidebar_style
        // sidebar` launch argument is never written to disk. Before the shell reads the mode.
        NavigationChrome.migrateLegacy(UserDefaults.standard, domain: Bundle.main.bundleIdentifier ?? "")

        // beta.19-rc1 verdict (F): `-debug.frameSamplerSteadyS N` opens a frame-timing window every
        // N s for the Soft-vs-Off frame-time gate. Inert unless that knob is set.
        CollectionFocusFrameSampler.shared.startSteadyWindowsIfConfigured()

        // FEAT-11: seed the shared hero-trailer audio state from the user's configured default
        // (PlaybackSettingsPane's "Trailer Sound by Default" toggle, same `trailer_audio_default_on`
        // key) so the very first trailer of a launch already respects it — DetailView otherwise
        // only restores this default after a full-screen trailer dismisses.
        HeroTrailerAudioState.shared.setMuted(value: !UserDefaults.standard.bool(forKey: "trailer_audio_default_on"))

        // Localize shared-module strings (toasts, month names, error messages…) through the
        // Shared string catalog. Without this, shared code uses its inline English fallbacks.
        LocalizedStrings.shared.provider = SharedStringProvider()

        // Wire the JS plugin stack (QuickJS runtime, tvosMain-only): scraper host for
        // StreamsRepository, cloud sync controller (plugin repos sync from mobile), and
        // profile-change/sign-out lifecycle hooks.
        TvOsPluginsInstallerKt.installTvOsPlugins()

        // BUG-74: attach the stream-diagnostics sink if the tester left the About toggle on. Inert
        // (sink stays nil) in every other case — see `StreamProbe`.
        StreamProbe.syncSink()

        // Configure + activate the audio session off the main thread once at startup. libmpv /
        // AVFoundation otherwise activate it lazily on the main thread at first playback, which
        // trips Xcode's "AVAudioSession Hang Risk" runtime diagnostic.
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }

        // Sweep remux session dirs orphaned by a jetsam kill or crash (cleanup normally runs on
        // playback stop, so anything under Caches/nuvio-remux at launch is a leak — and a single
        // remux-bitrate session can be several GB). Async on a utility queue; live sessions are
        // shielded via a registry.
        RemuxCacheJanitor.sweepAtLaunch()

        #if DEBUG
        // Phase 2 headless remux/HLS-server validation, gated on the `debug.remuxSmokeURL` default.
        RemuxSmokeTest.runIfRequested()
        #endif

        // BUG-59 (reveal gate): `debug.resetTrailerZoomStore` wipes the persisted per-title zoom
        // store at launch — the cold-store precondition the reveal-gate soak profile
        // (`TrailerSoakTests.testColdStoreFirstDwellRevealProfile`) and a device-pass repro need.
        // Honored only together with `debug.trailerProbe`, same discipline as
        // `debug.trailerSmokeVideoId` (a forgotten persisted knob must never be able to make a
        // release sideload re-measure every title forever).
        if TrailerProbe.enabled, UserDefaults.standard.bool(forKey: "debug.resetTrailerZoomStore") {
            TrailerZoomCache.shared.removeAll()
            NSLog("[TrailerZoom] store reset (debug.resetTrailerZoomStore)")
        }

        // BUG-128: trailer max-fps A/B leg (0 = as shipped); must precede the first extraction.
        TrailerExtractionPreferences.shared.maxVideoFps = Int32(TrailerTuning.maxFps)

        // Auth is started by AuthViewModel (ContentView.onAppear): existing guest installs
        // authenticate instantly from their stored anonymous id; otherwise the Supabase session is
        // restored, or the Welcome gate (Sign In / Create Account / Continue as Guest) is shown.
        // NOTE: we intentionally no longer call signInAnonymously() here — it generated a fresh
        // guest id on EVERY launch and shadowed real account sessions.
    }

    @ViewBuilder private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--navigation-layout-ui-test") {
            NavigationLayoutUITestFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--detail-layout-ui-test") {
            DetailLayoutUITestFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--live-tv-ui-test") {
            LiveTVView(profile: "live-tv-ui-test")
        } else if ProcessInfo.processInfo.arguments.contains("--live-player-ui-test") {
            LiveTVView(profile: "live-player-ui-test")
        } else if ProcessInfo.processInfo.arguments.contains("--nested-native-player-ui-test") {
            NestedPlayerUITestRoot(context: Self.playerTestContext)
        } else if ProcessInfo.processInfo.arguments.contains("--native-player-ui-test") {
            NativePlayerScreen(context: Self.playerTestContext)
        } else if ProcessInfo.processInfo.arguments.contains("--mpv-player-ui-test") {
            MPVPlayerScreen(context: Self.playerTestContext)
        } else if ProcessInfo.processInfo.arguments.contains("--player-panel-ui-test") {
            PlayerPanelUITestRoot(context: Self.playerTestContext)
        } else if ProcessInfo.processInfo.arguments.contains("--home-ui-test") {
            HomeUITestRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--addons-ui-test") {
            AddonsView()
        } else if ProcessInfo.processInfo.arguments.contains("--settings-ui-test") {
            SettingsUITestRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--search-ui-test") {
            SearchUITestRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--browse-ui-test") {
            BrowseUITestRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--welcome-ui-test") {
            WelcomeView(model: AuthViewModel())
        } else if ProcessInfo.processInfo.arguments.contains("--qr-sign-in-ui-test") {
            QrSignInView()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .providesFocusAppearance()
                // The app is a dark-canvas streaming UI (HIG: TV apps default dark). Pinning the
                // scheme makes every semantic color (.primary, .secondary, materials) resolve to
                // its dark variant regardless of the system appearance, so the semantic token
                // layer in Theme.swift can never land light-mode text on the dark backdrop.
                .preferredColorScheme(.dark)
        }
    }
    #if DEBUG
    private static var playerTestContext: PlaybackContext {
        PlaybackContext(url: URL(string: "http://127.0.0.1:8767/movie.mp4")!, title: "Player test film",
            contentType: "movie", parentMetaId: "player-ui-fixture", videoId: "player-ui-fixture",
            season: nil, episode: nil, poster: nil, background: nil, providerName: "Local fixture",
            providerAddonId: nil, streamTitle: nil, streamSubtitle: nil, externalSubtitles: [], recordsWatchProgress: false)
    }
    #endif

}

#if DEBUG
// Mirrors Home → Continue Watching source picker → player, including both presentation owners.
private struct NestedPlayerUITestRoot: View {
    let context: PlaybackContext
    @State private var sourcesOpen = false
    var body: some View {
        Button("Continue Watching") { sourcesOpen = true }
            .fullScreenCover(isPresented: $sourcesOpen) { NestedSourceUITestRoot(context: context) }
    }
}
private struct NestedSourceUITestRoot: View {
    let context: PlaybackContext
    @State private var playerOpen = false
    var body: some View {
        Button("First stream") { playerOpen = true }
            .fullScreenCover(isPresented: $playerOpen) { NativePlayerScreen(context: context) }
    }
}

private struct PlayerPanelUITestRoot: View {
    @StateObject private var model: PlayerTopPanelModel

    init(context: PlaybackContext) {
        var context = context
        context.synopsis = Array(repeating: "A long synopsis remains readable while moving through stream details with the remote, and scrolling back brings the title into view.", count: 6).joined(separator: " ")
        let model = PlayerTopPanelModel(info: PlayerPanelInfo(header: NativeInfoHeader(context: context)))
        model.info.rows = (1...20).map { NativeInfoRow(label: "Detail \($0)", value: "Stream information \($0)") }
        model.audio = (1...20).map { PlayerPanelOption(id: "\($0)", title: "Audio track \($0)", group: .audio, isSelected: $0 == 1) }
        model.subtitles = [PlayerPanelOption(id: "off", title: "Off", group: .off, isSelected: true)] +
            (1...20).map { PlayerPanelOption(id: "\($0)", title: "Subtitle track \($0)", group: .embedded, isSelected: false) }
        model.subtitlesSearching = false
        model.supportsSubtitleDelay = true
        model.onSelectAudio = { [weak model] selected in
            model?.audio = model?.audio.map { var option = $0; option.isSelected = option.id == selected.id; return option } ?? []
        }
        model.onSelectSubtitle = { [weak model] selected in
            model?.subtitles = model?.subtitles.map { var option = $0; option.isSelected = option.id == (selected?.id ?? "off"); return option } ?? []
        }
        model.onSubtitleDelayChange = { [weak model] in model?.subtitleDelayMs = $0 }
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        PlayerTopPanel(model: model, initialTab: .audio)
    }
}

private struct SettingsUITestRoot: View {
    @StateObject private var auth = AuthViewModel()
    @State private var path: [SettingsCategory] = []
    @State private var lastCategory: SettingsCategory?
    @State private var themeFocus: String?
    @State private var appearanceFocus: String?
    var body: some View {
        SettingsView(path: $path, lastCategory: $lastCategory, pendingThemeSwatchFocus: $themeFocus,
                     pendingAppearanceRowFocus: $appearanceFocus).environmentObject(auth)
    }
}
private struct HomeUITestRoot: View {
    @StateObject private var home = HomeViewModel()
    var body: some View { HomeView(model: home) }
}
private struct SearchUITestRoot: View {
    @StateObject private var home = HomeViewModel()
    @State private var visibility = TabBarVisibility()
    var body: some View {
        SearchView(home: home).environment(\.tabBarVisibility, visibility)
            .onAppear { visibility.setHomeTabSelected(false); visibility.setBrowseTabSelected(true) }
    }
}
private struct BrowseUITestRoot: View {
    @StateObject private var home = HomeViewModel()
    private var style: PosterStyle {
        var value = PosterStyle.default
        if ProcessInfo.processInfo.arguments.contains("--large-posters") {
            value.width *= 154.0 / 126.0
            value.height *= 154.0 / 126.0
        }
        return value
    }
    var body: some View { MediaBrowseView(model: home, mediaType: "movie").environment(\.posterStyle, style) }
}
#endif
