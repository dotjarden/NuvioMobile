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
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = channel.name as NSString
        item.externalMetadata = [title]
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
    @discardableResult func goLive() -> Bool {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return false }
        player.seek(to: CMTimeRangeGetEnd(range), toleranceBefore: .zero, toleranceAfter: .positiveInfinity); player.play()
        return true
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
    var onShowGuide: () -> Void = {}
    @StateObject private var model = LiveTVPlayer()
    @State private var channel: LiveTVChannel?
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
        ZStack {
            Color.black.ignoresSafeArea()
            if compatibilityPlayer {
                MPVPlayerScreen(context: compatibilityContext, liveActions: AnyView(compatibilityActions))
                    .id(active.id + playbackGeneration.uuidString).ignoresSafeArea()
            } else if let error = model.error {
                VStack(alignment: .leading, spacing: 28) {
                    Text(active.name).font(.title2.bold())
                    Text(error).font(.body)
                    HStack(spacing: 24) {
                        Button("Retry") { model.tune(active) }
                        Button("Compatibility player") { model.stop(); compatibilityPlayer = true; model.error = nil }
                        Button("Channel guide") { returnToGuide() }
                    }.buttonStyle(.glass).focusSection()
                }.padding(60).frame(maxWidth: 1300)
            } else {
                NativeLiveTVPlayer(player: model.player, channel: active, favorite: store.favorites.contains(active.id), canSwitch: channels.count > 1,
                    previous: { switchChannel(-1) }, next: { switchChannel(1) }, goLive: { if !model.goLive() { model.tune(active) } },
                    toggleFavorite: { store.toggleFavorite(active) }, guide: { returnToGuide() })
                    .ignoresSafeArea()
                if model.waiting { ProgressView("Connecting…").padding(25).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            compatibilityPlayer = ["ts", "mpeg", "mpg"].contains(active.url.pathExtension.lowercased())
            if !compatibilityPlayer { model.tune(active) }
            store.watched(active)
        }
        .onDisappear { model.stop() }
        .onExitCommand { dismiss() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
            else if phase == .active && !compatibilityPlayer { model.tune(active) }
        }
    }
    private func returnToGuide() { onShowGuide(); dismiss() }

    private var compatibilityActions: some View {
        LiveTVCompatibilityActions(store: store, channel: active, canSwitch: channels.count > 1,
            previous: { switchChannel(-1) }, next: { switchChannel(1) }, goLive: { playbackGeneration = UUID() }, guide: { returnToGuide() })
    }
    private func switchChannel(_ step: Int) {
        guard !channels.isEmpty else { return }
        let index = channels.firstIndex(where: { $0.id == active.id }) ?? 0
        channel = channels[(index + step + channels.count) % channels.count]
        if !compatibilityPlayer { model.tune(active) }; store.watched(active)
    }
}

/// AVKit owns presentation, placement, and focus for these actions. Never layer a second
/// SwiftUI transport bar over AVPlayerViewController (or over MPV's existing controls).
private struct NativeLiveTVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let channel: LiveTVChannel
    let favorite: Bool
    let canSwitch: Bool
    let previous: () -> Void
    let next: () -> Void
    let goLive: () -> Void
    let toggleFavorite: () -> Void
    let guide: () -> Void
    final class Coordinator { var menuKey = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        updateUIViewController(controller, context: context)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        let key = "\(channel.id):\(favorite):\(canSwitch)"
        guard context.coordinator.menuKey != key else { return }
        context.coordinator.menuKey = key
        let actions = [
            UIAction(title: "Previous channel", image: UIImage(systemName: "backward.end"), attributes: canSwitch ? [] : [.disabled]) { _ in previous() },
            UIAction(title: "Next channel", image: UIImage(systemName: "forward.end"), attributes: canSwitch ? [] : [.disabled]) { _ in next() },
            UIAction(title: "Go Live", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { _ in goLive() },
            UIAction(title: favorite ? "Remove favorite" : "Favorite channel", image: UIImage(systemName: favorite ? "star.fill" : "star")) { _ in toggleFavorite() },
            UIAction(title: "Channel guide", image: UIImage(systemName: "list.bullet.rectangle")) { _ in guide() }
        ]
        controller.transportBarCustomMenuItems = [UIMenu(title: "Live TV", image: UIImage(systemName: "tv"), children: actions)]
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.transportBarCustomMenuItems = []
        controller.player = nil
    }
}

/// Compatibility playback uses MPV's existing Playback panel, never a competing overlay.
private struct LiveTVCompatibilityActions: View {
    @ObservedObject var store: LiveTVStore
    let channel: LiveTVChannel
    let canSwitch: Bool
    let previous: () -> Void
    let next: () -> Void
    let goLive: () -> Void
    let guide: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(channel.name).font(.headline)
            HStack(spacing: 24) {
                Button("Previous channel", action: previous).disabled(!canSwitch)
                Button("Next channel", action: next).disabled(!canSwitch)
                Button("Go Live", action: goLive)
            }.focusSection()
            HStack(spacing: 24) {
                Button(store.favorites.contains(channel.id) ? "Remove favorite" : "Favorite channel") { store.toggleFavorite(channel) }
                Button("Channel guide", action: guide)
            }.focusSection()
        }.padding(28).background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
