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
            } else {
                NativeLiveTVPlayer(player: model.player, playbackContext: compatibilityContext,
                                   playbackActions: AnyView(compatibilityActions))
                    .id(active.id)
                    .ignoresSafeArea()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            compatibilityPlayer = ["ts", "mpeg", "mpg"].contains(active.url.pathExtension.lowercased())
            if !compatibilityPlayer { model.tune(active) }
            store.watched(active)
        }
        .onDisappear { model.stop() }
        .onChange(of: model.error) { _, error in
            guard error != nil, !compatibilityPlayer else { return }
            model.stop()
            compatibilityPlayer = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
            else if phase == .active && !compatibilityPlayer { model.tune(active) }
        }
    }
    private func returnToGuide() { onShowGuide(); dismiss() }

    private var compatibilityActions: some View {
        LiveTVCompatibilityActions(store: store, channel: active, canSwitch: channels.count > 1,
            previous: { switchChannel(-1) }, next: { switchChannel(1) }, goLive: { if compatibilityPlayer { playbackGeneration = UUID() } else { model.goLive() } }, guide: { returnToGuide() })
    }
    private func switchChannel(_ step: Int) {
        guard !channels.isEmpty else { return }
        let index = channels.firstIndex(where: { $0.id == active.id }) ?? 0
        channel = channels[(index + step + channels.count) % channels.count]
        if !compatibilityPlayer { model.tune(active) }; store.watched(active)
    }
}

/// Native live playback uses the same Settings entry point and bottom drawer as movie playback.
private struct NativeLiveTVPlayer: View {
    let player: AVPlayer
    let playbackContext: PlaybackContext
    let playbackActions: AnyView
    @StateObject private var state: PlayerPlaybackState
    @StateObject private var model: PlayerTopPanelModel
    @State private var adapter: LivePlayerPanelAdapter?
    @Environment(\.dismiss) private var dismiss

    init(player: AVPlayer, playbackContext: PlaybackContext, playbackActions: AnyView) {
        self.player = player
        self.playbackContext = playbackContext
        self.playbackActions = playbackActions
        let state = PlayerPlaybackState(title: playbackContext.title)
        state.isLive = true
        _state = StateObject(wrappedValue: state)
        _model = StateObject(wrappedValue: PlayerTopPanelModel(info: PlayerPanelInfo(header: NativeInfoHeader(context: playbackContext))))
    }

    var body: some View {
        ZStack {
            AVPlayerSurface(player: player, state: state).ignoresSafeArea()
            PlayerChrome(state: state, context: playbackContext, panelModel: model,
                         extraTab: PlayerPanelExtraTab { playbackActions },
                         onExit: { dismiss() })
        }
        .onAppear {
            adapter = LivePlayerPanelAdapter(player: player, model: model, context: playbackContext)
            state.performDownAction = { [weak state] in state?.reveal() }
        }
        .onDisappear { adapter = nil }
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
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 20) {
                if let logo = channel.logo {
                    CachedAsyncImage(string: logo.absoluteString, contentMode: .fit)
                        .frame(width: 84, height: 64)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.title3.bold())
                    if !channel.group.isEmpty {
                        Text(channel.group).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
            }
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 16) {
                    PlayerPanelSectionCaption(text: "Channel")
                    HStack(spacing: 20) {
                        Button(action: previous) { Label("Previous", systemImage: "backward.end") }
                            .accessibilityLabel("Previous channel").disabled(!canSwitch)
                        Button("Go Live", action: goLive)
                        Button(action: next) { Label("Next", systemImage: "forward.end") }
                            .accessibilityLabel("Next channel").disabled(!canSwitch)
                    }
                }.focusSection()
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 16) {
                    PlayerPanelSectionCaption(text: "Browse")
                    HStack(spacing: 20) {
                        Button { store.toggleFavorite(channel) } label: {
                            Label(store.favorites.contains(channel.id) ? "Favorited" : "Favorite", systemImage: store.favorites.contains(channel.id) ? "star.fill" : "star")
                        }
                        .accessibilityLabel(store.favorites.contains(channel.id) ? "Remove favorite" : "Favorite channel")
                        Button(action: guide) { Label("Guide", systemImage: "list.bullet.rectangle") }
                            .accessibilityLabel("Channel guide")
                    }
                }.focusSection()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 12)
    }
}
