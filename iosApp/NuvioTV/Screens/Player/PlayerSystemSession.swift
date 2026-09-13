import Combine
import MediaPlayer

/// System Now Playing and external remote commands share the same transport commands as the UI.
@MainActor final class PlayerSystemSession {
    private let state: PlayerPlaybackState
    private let context: PlaybackContext
    private var targets: [(MPRemoteCommand, Any)] = []
    private var updates: AnyCancellable?

    init(state: PlayerPlaybackState, context: PlaybackContext) {
        self.state = state
        self.context = context
        let commands = MPRemoteCommandCenter.shared()
        register(commands.togglePlayPauseCommand) { $0.togglePlayback?() }
        register(commands.playCommand) { if $0.isPaused { $0.togglePlayback?() } }
        register(commands.pauseCommand) { if !$0.isPaused { $0.togglePlayback?() } }
        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.preferredIntervals = [10]
        register(commands.skipForwardCommand) { $0.seekRelative?(10) }
        register(commands.skipBackwardCommand) { $0.seekRelative?(-10) }
        updates = state.objectWillChange
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                Task { @MainActor in self?.publish() }
            }
        publish()
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (PlayerPlaybackState) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                action(self.state)
            }
            return .success
        }
        targets.append((command, target))
    }

    private func publish() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: context.title,
            MPNowPlayingInfoPropertyIsLiveStream: context.isLive,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.positionSec,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPaused ? 0 : state.playbackSpeed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
        if !context.isLive { info[MPMediaItemPropertyPlaybackDuration] = state.durationSec }
        if let subtitle = context.transportSubtitle { info[MPMediaItemPropertyAlbumTitle] = subtitle }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func stop() {
        updates = nil
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
