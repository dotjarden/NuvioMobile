import AVKit
import SwiftUI

/// A video-only layer: no AVKit responder, transport overlay, or competing remote handler.
struct AVPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let state: PlayerPlaybackState

    func makeCoordinator() -> AVPlayerTransportAdapter {
        AVPlayerTransportAdapter(player: player, state: state)
    }

    func makeUIView(context: Context) -> PlayerVideoView {
        let view = PlayerVideoView()
        view.playerLayer.player = player
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: PlayerVideoView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleUIView(_ view: PlayerVideoView, coordinator: AVPlayerTransportAdapter) {
        coordinator.stop()
        view.playerLayer.player = nil
    }
}

final class PlayerVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var displayTask: Task<Void, Never>?
    private var readyObservation: NSKeyValueObservation?
    private weak var displayWindow: UIWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayTask?.cancel()
        readyObservation = nil
        displayWindow?.avDisplayManager.preferredDisplayCriteria = nil
        displayWindow = window
        guard window != nil, UserDefaults.standard.bool(forKey: PlayerTuning.matchFrameRateKey) else { return }
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in self?.matchContent() }
        }
    }

    private func matchContent() {
        displayTask?.cancel()
        guard let item = playerLayer.player?.currentItem else { return }
        displayTask = Task { [weak self] in
            guard let track = try? await item.asset.loadTracks(withMediaType: .video).first,
                  let fps = try? await track.load(.nominalFrameRate),
                  let format = try? await track.load(.formatDescriptions).first,
                  !Task.isCancelled, let self, self.playerLayer.player?.currentItem === item,
                  fps > 0 else { return }
            self.displayWindow?.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: fps, formatDescription: format)
        }
    }
}

/// Normalizes AVPlayer transport into the same state/commands used by libmpv.
@MainActor final class AVPlayerTransportAdapter {
    private let player: AVPlayer
    private let state: PlayerPlaybackState
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var hasStartedPlaying = false

    init(player: AVPlayer, state: PlayerPlaybackState) {
        self.player = player
        self.state = state
        state.togglePlayback = { [weak self] in
            guard let self else { return }
            if self.player.rate == 0 { self.player.playImmediately(atRate: self.player.defaultRate) }
            else { self.player.pause() }
            self.refresh()
            self.state.reveal()
        }
        state.seekRelative = { [weak self] offset in self?.seek(offset) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver = nil
        state.togglePlayback = nil
        state.seekRelative = nil
    }

    private func refresh() {
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        state.positionSec = position.isFinite ? max(0, position) : 0
        if state.isLive, let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue {
            state.seekableStartSec = range.start.seconds
            state.durationSec = CMTimeRangeGetEnd(range).seconds
        } else {
            state.seekableStartSec = 0
            state.durationSec = duration.isFinite ? max(0, duration) : 0
        }
        state.playbackSpeed = Double(player.defaultRate)
        if player.timeControlStatus == .playing { hasStartedPlaying = true }
        state.isPaused = hasStartedPlaying && player.timeControlStatus == .paused
        state.isBuffering = !hasStartedPlaying || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    private func seek(_ offset: Double) {
        refresh()
        guard state.durationSec > state.seekableStartSec else { state.reveal(); return }
        if offset < 0 { state.upNextCancel?() }
        let target = min(max(state.positionSec + offset, state.seekableStartSec), state.durationSec)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        state.positionSec = target
        state.reveal()
    }
}
