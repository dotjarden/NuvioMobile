import SharedCore
import AVKit
import SwiftUI

#if DEBUG
/// UI-level player smoke: when `debug.mpvSmokeURL` holds a source URL, the root view presents the
/// real `PlayerScreen` (engine routing included) shortly after launch. The native engine is ON by
/// default (beta.13+), so compatible files land on the native AVPlayer screen — handy for headed
/// info-panel checks; write `player.nativeDolbyVision -bool NO` first to force the full libmpv
/// path: event-driven property cache, track-list walks on the event queue, progress saves, and
/// the `[MPVStats]` first-90s diagnostics.
///
/// Sim workflow (mirrors `debug.remuxSmokeURL` — see RemuxSmokeTest.swift):
///   xcrun simctl spawn <dev> defaults write com.nuvio.media.NuvioTV debug.mpvSmokeURL -string '<url>'
///   xcrun simctl launch --console-pty <dev> com.nuvio.media.NuvioTV     # grep [MPVSmoke]/[MPVStats]
///   xcrun simctl spawn <dev> defaults delete com.nuvio.media.NuvioTV debug.mpvSmokeURL
///
/// `debug.mpvSmokeDelaySec` (default 2) holds presentation until app bootstrap settles.
struct MPVSmokeModifier: ViewModifier {
    @State private var context: PlaybackContext?
    @State private var armed = false
    /// `debug.avplayerUIURL`: present a bare AVPlayerViewController on an arbitrary URL (e.g. Apple's
    /// reference HLS stream) — a control for what the SIMULATOR's system panel shows (Subtitles /
    /// Audio tabs) independent of our synthesized master.
    @State private var bareURL: URL?
    /// `debug.mpvSmokePostPlay` YES (P5 B22 legs): the id of the post-play More Like This title
    /// the player handed back, shown by the 1 pt `debug_postPlayOpened` label.
    @State private var smokeOpened = ""

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !armed, let raw = UserDefaults.standard.string(forKey: "debug.avplayerUIURL"), let url = URL(string: raw) {
                    armed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { bareURL = url }
                    return
                }
                guard !armed,
                      let raw = UserDefaults.standard.string(forKey: "debug.mpvSmokeURL"),
                      let url = URL(string: raw) else { return }
                armed = true
                let delay = max(UserDefaults.standard.double(forKey: "debug.mpvSmokeDelaySec"), 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    print("[MPVSmoke] presenting PlayerScreen for \(url)")
                    let poster = UserDefaults.standard.string(forKey: "debug.mpvSmokePosterURL")
                    // `debug.mpvSmokeSeries` YES (P5 B23 legs): a series context, so the
                    // Remember Speed row shows. Movies (the default) never show it.
                    let smokeSeries = UserDefaults.standard.bool(forKey: "debug.mpvSmokeSeries")
                    // `debug.mpvSmokeSubtitleURL` <url> (P5 B19 legs): one external "Smoke EN" subtitle.
                    let smokeSubtitles: [SubtitleFile] = UserDefaults.standard
                        .string(forKey: "debug.mpvSmokeSubtitleURL")
                        .map { [SubtitleFile(url: $0, language: "en", name: "Smoke EN")] } ?? []
                    var ctx = PlaybackContext(
                        url: url, title: "MPV Smoke", contentType: smokeSeries ? "series" : "movie",
                        parentMetaId: smokeSeries ? "smoke-series" : "smoke-mpv",
                        videoId: smokeSeries ? "smoke-series:1:1" : "smoke-mpv",
                        season: smokeSeries ? 1 : nil, episode: smokeSeries ? 1 : nil, poster: poster, background: nil,
                        providerName: nil, providerAddonId: nil,
                        streamTitle: "Smoke.Release.2160p.WEB-DL", streamSubtitle: nil, externalSubtitles: smokeSubtitles,
                        // Info-tab header content for headed sim checks (poster optional).
                        synopsis: "Headless smoke run. This synopsis exists so the native player's Info tab header can be checked in the simulator without a signed-in catalog."
                    )
                    // `debug.mpvSmokeStartOver`: ignore the saved progress of earlier runs. The UI
                    // legs set it so a hold-step leg never starts a few seconds before the
                    // fixture's end (the P1 legs hit EOF once the saved position passed ~560 s).
                    ctx.startFromBeginning = UserDefaults.standard.bool(forKey: "debug.mpvSmokeStartOver")
                    // `debug.mpvSmokeAudioDelayMs` <int> (P5 N1 legs): a stream audio-delay hint.
                    if UserDefaults.standard.object(forKey: "debug.mpvSmokeAudioDelayMs") != nil {
                        ctx.streamAudioDelayMs = UserDefaults.standard.integer(forKey: "debug.mpvSmokeAudioDelayMs")
                    }
                    // `debug.mpvSmokeEngine` native|mpv (P4 legs): force the engine. A forced
                    // native engine skips the probe and the silent mpv fallback
                    // (`PlayerScreen.shown`), so a native leg can never quietly pass on mpv.
                    switch UserDefaults.standard.string(forKey: "debug.mpvSmokeEngine")?.lowercased() {
                    case "native": ctx.forcedEngine = .native
                    case "mpv": ctx.forcedEngine = .mpv
                    default: break
                    }
                    // `debug.mpvSmokeResumeSec` <sec> (P5 B22 legs): start near the end of a short fixture.
                    if UserDefaults.standard.object(forKey: "debug.mpvSmokeResumeSec") != nil {
                        ctx.resumeAtSec = UserDefaults.standard.double(forKey: "debug.mpvSmokeResumeSec")
                    }
                    if let forced = ctx.forcedEngine { print("[MPVSmoke] forced engine: \(forced)") }
                    context = ctx
                }
            }
            .fullScreenCover(item: $context) { ctx in
                PlayerScreen(
                    context: ctx, onPlayNext: { _ in },
                    // `debug.mpvSmokePostPlay` YES: enable the More Like This row; a pick is
                    // recorded in `smokeOpened` instead of pushing a page.
                    onOpenTitle: UserDefaults.standard.bool(forKey: "debug.mpvSmokePostPlay")
                        ? { smokeOpened = $0.id } : nil
                )
                .ignoresSafeArea()
            }
            .overlay(alignment: .topLeading) {
                if UserDefaults.standard.bool(forKey: "debug.mpvSmokePostPlay") {
                    Text(smokeOpened.isEmpty ? "none" : smokeOpened)
                        .font(.system(size: 1))
                        .opacity(0.01)
                        .accessibilityIdentifier("debug_postPlayOpened")
                }
            }
            .fullScreenCover(item: $bareURL) { url in
                BareAVPlayerView(url: url).ignoresSafeArea()
            }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

private struct BareAVPlayerView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.player?.play()
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
#endif
