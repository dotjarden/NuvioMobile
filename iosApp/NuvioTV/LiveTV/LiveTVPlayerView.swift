import SwiftUI
import AVKit
import Combine

/// Live sessions deliberately bypass PlaybackProgressRecorder, Trakt, and next-episode logic.
@MainActor final class LiveTVPlayer: ObservableObject {
    let player = AVPlayer()
    @Published var error: String?
    @Published var waiting = true
    private var status: NSKeyValueObservation?
    private var waitingObservation: NSKeyValueObservation?
    private var endFailure: NSObjectProtocol?
    private var generation = UUID()
    func tune(_ channel: LiveTVChannel) {
        stop()
        let token = UUID(); generation = token
        error = nil; waiting = true
        let asset = AVURLAsset(url: channel.url, options: channel.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": channel.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5
        status = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if item.status == .failed {
                    self.error = "This channel could not be played. Try again or choose another channel."
                    self.waiting = false
                }
            }
        }
        waitingObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        endFailure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.error = "The channel connection was interrupted. Try again to reconnect."; self.waiting = false
            }
        }
        player.replaceCurrentItem(with: item); player.play()
    }
    func goLive() {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        player.seek(to: CMTimeRangeGetEnd(range), toleranceBefore: .zero, toleranceAfter: .positiveInfinity); player.play()
    }
    func stop() {
        generation = UUID(); waiting = false
        status?.invalidate(); status = nil; waitingObservation?.invalidate(); waitingObservation = nil
        if let endFailure { NotificationCenter.default.removeObserver(endFailure) }; endFailure = nil
        player.pause(); player.replaceCurrentItem(with: nil)
    }
}

struct LiveTVPlayerView: View {
    @ObservedObject var store: LiveTVStore
    let initialChannel: LiveTVChannel
    let channels: [LiveTVChannel]
    @StateObject private var model = LiveTVPlayer()
    @State private var channel: LiveTVChannel?
    @State private var controlsVisible = true
    @State private var compatibilityPlayer = false
    @State private var playbackGeneration = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var active: LiveTVChannel { channel ?? initialChannel }
    private var compatibilityContext: PlaybackContext {
        var context = PlaybackContext(url: active.url, title: active.name, contentType: "tv", parentMetaId: active.id,
            videoId: active.id, season: nil, episode: nil, poster: active.logo?.absoluteString, background: nil,
            providerName: "Live TV", providerAddonId: nil, streamTitle: active.name, streamSubtitle: nil, externalSubtitles: [])
        context.requestHeaders = active.headers; context.isLive = true
        return context
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            if compatibilityPlayer {
                MPVPlayerScreen(context: compatibilityContext).id(active.id + playbackGeneration.uuidString).ignoresSafeArea()
            } else {
                NativeLiveTVPlayer(player: model.player).ignoresSafeArea()
            }
            if model.waiting && !compatibilityPlayer { ProgressView("Connecting…").padding(25).glassEffect().frame(maxHeight: .infinity) }
            if controlsVisible || model.error != nil {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Label("Live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.red); Text(active.name).font(.title2.bold()); Spacer() }
                    if let programme = store.schedule(for: active).first, programme.isCurrent(at: Date()) { Text(programme.title).foregroundStyle(.secondary) }
                    if let error = model.error { Text(error) }
                    HStack(spacing: 20) {
                        Button { switchChannel(-1) } label: { Label("Previous", systemImage: "backward.end") }.disabled(channels.count < 2)
                        Button { switchChannel(1) } label: { Label("Next", systemImage: "forward.end") }.disabled(channels.count < 2)
                        Button("Go live") { if compatibilityPlayer { playbackGeneration = UUID() } else { model.goLive() } }
                        if model.error != nil {
                            Button("Retry") { model.tune(active) }
                            Button("Compatibility player") { model.stop(); compatibilityPlayer = true; model.error = nil }
                        }
                        Button { store.toggleFavorite(active) } label: { Image(systemName: store.favorites.contains(active.id) ? "star.fill" : "star") }.accessibilityLabel("Toggle favorite")
                        Button("Guide") { dismiss() }
                        Button("Hide") { controlsVisible = false }
                    }.buttonStyle(.glass)
                }.padding(30).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28)).padding(45)
            }
        }
        .onAppear {
            compatibilityPlayer = ["ts", "mpeg", "mpg"].contains(active.url.pathExtension.lowercased())
            if !compatibilityPlayer { model.tune(active) }
            store.watched(active)
        }
        .onDisappear { model.stop() }
        .onExitCommand { if !controlsVisible { controlsVisible = true } else { dismiss() } }
        .onMoveCommand { direction in if direction == .down || direction == .up { controlsVisible = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
            else if phase == .active && !compatibilityPlayer { model.tune(active) }
        }
    }
    private func switchChannel(_ step: Int) {
        guard !channels.isEmpty else { return }
        let index = channels.firstIndex(where: { $0.id == active.id }) ?? 0
        channel = channels[(index + step + channels.count) % channels.count]
        if !compatibilityPlayer { model.tune(active) }; store.watched(active)
    }
}

private struct NativeLiveTVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController(); controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}
