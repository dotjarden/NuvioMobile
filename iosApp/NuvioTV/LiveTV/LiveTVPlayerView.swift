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
                NativeLiveTVPlayer(player: model.player, playbackContext: compatibilityContext,
                                   playbackActions: AnyView(compatibilityActions))
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

/// Native live playback uses the same Settings entry point and bottom drawer as movie playback.
private struct NativeLiveTVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let playbackContext: PlaybackContext
    let playbackActions: AnyView
    final class Coordinator {
        let model: PlayerTopPanelModel
        var adapter: LivePlayerPanelAdapter?
        var item: AVPlayerItem?
        init(context: PlaybackContext) {
            model = PlayerTopPanelModel(info: PlayerPanelInfo(header: NativeInfoHeader(context: context)))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(context: playbackContext) }
    func makeUIViewController(context: Context) -> NativePlayerHostController {
        let host = NativePlayerHostController()
        host.playerVC.player = player
        updateUIViewController(host, context: context)
        return host
    }
    func updateUIViewController(_ host: NativePlayerHostController, context: Context) {
        if host.playerVC.player !== player { host.playerVC.player = player }
        let coordinator = context.coordinator
        if coordinator.item !== player.currentItem {
            host.closePanel(animated: false)
            coordinator.item = player.currentItem
            coordinator.adapter = LivePlayerPanelAdapter(player: player, model: coordinator.model, context: playbackContext)
        }
        let model = coordinator.model, actions = playbackActions
        host.onOpenPanel = { [weak host] tab in
            guard let host else { return }
            let panel = PlayerPanelHostController(rootView: PlayerTopPanel(model: model,
                extraTab: PlayerPanelExtraTab(maximumWidth: 1100) { actions }, initialTab: tab))
            model.onClose = { [weak panel] in panel?.close(animated: true) }
            host.present(panel: panel)
        }
    }
    static func dismantleUIViewController(_ host: NativePlayerHostController, coordinator: Coordinator) {
        host.closePanel(animated: false)
        coordinator.adapter = nil
        host.playerVC.player = nil
    }
}

/// Direct AVPlayer media selections for live streams; no movie progress or scrobbling pipeline.
@MainActor private final class LivePlayerPanelAdapter {
    private let player: AVPlayer
    private let model: PlayerTopPanelModel
    private var audible: AVMediaSelectionGroup?
    private var legible: AVMediaSelectionGroup?
    private var loadTask: Task<Void, Never>?
    private var status: NSKeyValueObservation?
    private var detailsTimer: Timer?

    init(player: AVPlayer, model: PlayerTopPanelModel, context: PlaybackContext) {
        self.player = player; self.model = model
        model.info = PlayerPanelInfo(header: NativeInfoHeader(context: context), chips: [PlayerPanelChip(text: "LIVE")])
        model.subtitlesSearching = false
        model.supportsSubtitleDelay = false
        model.audio = []; model.subtitles = []
        model.onSelectAudio = { [weak self] option in
            guard let self, let group = self.audible, let index = Int(option.id), group.options.indices.contains(index) else { return }
            self.player.currentItem?.select(group.options[index], in: group)
            self.updateSelections()
        }
        model.onSelectSubtitle = { [weak self] option in
            guard let self, let group = self.legible else { return }
            let selected = option.flatMap { Int($0.id) }.flatMap { group.options.indices.contains($0) ? group.options[$0] : nil }
            self.player.currentItem?.select(selected, in: group)
            self.updateSelections()
        }
        model.hasNativeSoundOptions = true
        model.onPresentation = { [weak self] in self?.updateSelections() }
        model.onDetailsVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.detailsTimer?.invalidate(); self.detailsTimer = nil
            if visible {
                self.updateDetails()
                self.detailsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.updateDetails() }
                }
            }
        }
        status = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in self?.loadSelections() }
        }
    }
    deinit { loadTask?.cancel(); status?.invalidate(); detailsTimer?.invalidate() }

    private func loadSelections() {
        loadTask?.cancel()
        guard let item = player.currentItem else { return }
        loadTask = Task { [weak self] in
            let audio = try? await item.asset.loadMediaSelectionGroup(for: .audible)
            let subtitles = try? await item.asset.loadMediaSelectionGroup(for: .legible)
            guard !Task.isCancelled, let self, self.player.currentItem === item else { return }
            self.audible = audio; self.legible = subtitles
            self.updateSelections()
        }
    }
    private func updateSelections() {
        guard let item = player.currentItem else { return }
        if let audible {
            let selected = item.currentMediaSelection.selectedMediaOption(in: audible)
            model.audio = audible.options.enumerated().map { index, option in
                PlayerPanelOption(id: String(index), title: option.displayName, group: .audio, isSelected: option == selected)
            }
        }
        if let legible {
            let selected = item.currentMediaSelection.selectedMediaOption(in: legible)
            model.subtitles = [PlayerPanelOption(id: "off", title: String(localized: "Off"), group: .off, isSelected: selected == nil)]
                + legible.options.enumerated().map { index, option in
                    PlayerPanelOption(id: String(index), title: option.displayName, group: .embedded, isSelected: option == selected)
                }
        }
        model.outputRouteName = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ")
    }
    private func updateDetails() {
        guard model.detailsVisible, let item = player.currentItem else { return }
        let size = item.presentationSize
        var rows = [NativeInfoRow(label: "Engine", value: "Native"),
                    NativeInfoRow(label: "Status", value: player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? "Buffering" : "Live")]
        if size.width > 0 { rows.append(NativeInfoRow(label: "Resolution", value: "\(Int(size.width)) × \(Int(size.height))")) }
        if let event = item.accessLog()?.events.last, event.indicatedBitrate > 0 {
            rows.append(NativeInfoRow(label: "Bitrate", value: String(format: "%.1f Mbps", event.indicatedBitrate / 1_000_000)))
        }
        if model.info.rows != rows { model.info.rows = rows }
    }
}

/// Live actions occupy the same Playback drawer on both decoding engines.
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
        }.padding(.vertical, 20)
    }
}
