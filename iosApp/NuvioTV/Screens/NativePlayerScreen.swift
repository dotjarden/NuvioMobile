import AVKit
import Combine
import SharedCore
import SwiftUI

// Native decoding and progress remain in the coordinator. PlayerChrome is shared with MPV and Live TV.
struct NativePlayerScreen: View {
    let context: PlaybackContext
    var onPlayNext: ((PlaybackContext) -> Void)?
    /// Called with the last known position when the native path can't play — dispatcher → mpv.
    var onFallback: ((Double) -> Void)?
    /// Router decision label (e.g. "Native · DV P7 FEL → 8.1") for the Info tab.
    var routingNote: String?

    @StateObject private var coordinator: NativePlaybackCoordinator
    @StateObject private var upNext: NextEpisodeEngine
    @StateObject private var panelModel: PlayerTopPanelModel
    @State private var panelAdapter: NativePlayerPanelAdapter?
    @State private var skipSegments: [SkipSegment] = []
    @State private var skipPrompt: SkipPrompt?
    @StateObject private var state: PlayerPlaybackState
    @Environment(\.dismiss) private var dismiss

    init(context: PlaybackContext,
         onPlayNext: ((PlaybackContext) -> Void)? = nil,
         onFallback: ((Double) -> Void)? = nil,
         routingNote: String? = nil) {
        self.context = context
        _state = StateObject(wrappedValue: PlayerPlaybackState(title: context.title))
        self.onPlayNext = onPlayNext
        self.onFallback = onFallback
        self.routingNote = routingNote
        _coordinator = StateObject(wrappedValue: NativePlaybackCoordinator(context: context))
        _upNext = StateObject(wrappedValue: NextEpisodeEngine(context: context, onPlayNext: onPlayNext ?? { _ in }))
        _panelModel = StateObject(wrappedValue: PlayerTopPanelModel(
            info: PlayerPanelInfo(header: NativeInfoHeader(context: context))))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch coordinator.phase {
            case .preparing:
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.6)
                    Text("Preparing playback…")
                        .font(Theme.Font.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
            case .playing:
                if let player = coordinator.player {
                    AVPlayerSurface(player: player, state: state).ignoresSafeArea()
                    PlayerChrome(state: state, context: context, panelModel: panelModel,
                                 extraTab: PlayerPanelExtraTab {
                        NativePlaybackOptions(player: player, engine: upNext, canSwitchStreams: onPlayNext != nil,
                                              onClose: { panelModel.onClose?() })
                    }, onExit: { dismiss() })

                }
            case .failed:
                // Hand back to the dispatcher, which re-presents the mpv player for this context.
                Color.clear.onAppear {
                    if let onFallback { onFallback(coordinator.lastPositionSec) } else { dismiss() }
                }
            }

            if !state.panelOpen {
                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    if let caption = upNext.phase.chipCaption(nextTitle: upNext.nextEpisodeTitle) {
                        PlayerChipCaption(text: caption.text, symbol: caption.symbol, showsProgress: caption.progress)
                    }
                    if let action = upNextAction {
                        PlayerActionChip(label: action.title, symbol: PlayerChipStyle.nextSymbol, showsPressHint: true)
                    } else if let prompt = skipPrompt {
                        PlayerActionChip(label: prompt.label, symbol: PlayerChipStyle.skipSymbol, showsPressHint: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(PlayerChipStyle.edgePadding)
                .allowsHitTesting(false)
            }

        }
        .animation(PlayerChipStyle.animation, value: upNext.phase)
        .onAppear {
            let adapter = NativePlayerPanelAdapter(coordinator: coordinator, model: panelModel,
                                                   context: context, routingNote: routingNote)
            panelAdapter = adapter
            coordinator.onTick = { [weak upNext, weak adapter] position, duration in
                upNext?.onProgress(positionSec: position, durationSec: duration)
                updateSkipPrompt(position: position)
                adapter?.onTick()
            }
            state.upNextDismiss = { [weak upNext] in upNext?.dismissIfVisible() ?? false }
            state.upNextCancel = { [weak upNext] in upNext?.cancel() }
            state.performDownAction = {
                if upNext.playNow() { return }
                if let prompt = skipPrompt {
                    coordinator.player?.seek(to: CMTime(seconds: prompt.targetSec, preferredTimescale: 600))
                }
                state.reveal()
            }
            coordinator.start()
            // Only orchestrate up-next when a presenter can swap contexts (series autoplay).
            if onPlayNext != nil { upNext.startNative() }
            fetchSkipSegments()
        }
        .onDisappear {
            coordinator.stop()
            upNext.stop()
        }
    }

    /// Which up-next contextual action to offer: "Play Next Episode" during the countdown,
    /// "Continue Watching" once the still-watching guard has paused autoplay, none otherwise.
    private var upNextAction: UpNextAction? {
        switch upNext.phase {
        case .counting: return .playNext
        case .stillWatching: return .continueWatching
        default: return nil
        }
    }

    // MARK: - Skip intro/outro segments (shared repository, same rules as the mpv screen)

    /// Fetch intro/recap/outro segments for a series episode (no-op for movies / missing episode
    /// numbers). Respects the Settings > Playback "Skip Intro" toggle.
    private func fetchSkipSegments() {
        guard let season = context.season, let episode = context.episode else { return }
        SkipIntroRepository.shared.getSkipIntervalsForContentId(
            // Routes kitsu:/mal: anime ids to the anime providers (same rules as the mpv screen).
            contentId: context.parentMetaId,
            season: Int32(season),
            episode: Int32(episode),
            requireSkipIntroEnabled: true
        ) { intervals, _ in
            let segments = (intervals ?? []).map { SkipSegment(start: $0.startTime, end: $0.endTime, type: $0.type) }
            print("[NativePlayer] skip segments: \(segments.count)"
                  + (segments.isEmpty ? " (none in intro DB for this episode)" : ""))
            guard !segments.isEmpty else { return }
            DispatchQueue.main.async { self.skipSegments = segments }
        }
    }

    /// Offer the skip while inside a segment; the last second is excluded so the action
    /// disappears cleanly at the end (same rule as the mpv screen).
    private func updateSkipPrompt(position: Double) {
        let active = skipSegments.first { position >= $0.start && position < $0.end - PlayerChipStyle.lastSecondExclusion }
        let prompt = active.map { SkipPrompt(label: Self.skipLabel(for: $0.type), targetSec: $0.end) }
        if prompt != skipPrompt { skipPrompt = prompt }
    }

    private static func skipLabel(for type: String) -> String {
        switch type.lowercased() {
        case "outro", "ed", "credits": return String(localized: "Skip Outro")
        case "recap": return String(localized: "Skip Recap")
        default: return String(localized: "Skip Intro")
        }
    }
}

/// Up-next contextual action variants (static titles — see the caption note in `NativePlayerScreen`).
enum UpNextAction: String {
    case playNext, continueWatching

    var title: String {
        switch self {
        case .playNext: return String(localized: "Play Next Episode")
        case .continueWatching: return String(localized: "Continue Watching")
        }
    }
}

private struct NativePlaybackOptions: View {
    let player: AVPlayer
    @ObservedObject var engine: NextEpisodeEngine
    let canSwitchStreams: Bool
    let onClose: () -> Void
    @State private var speed = 1.0
    var body: some View {
        PlayerPlaybackTab(playbackSpeed: speed, audioDelaySec: nil, onSpeed: { value in
            speed = value
            player.defaultRate = Float(value)
            if player.rate != 0 { player.rate = Float(value) }
        }, onAudioDelay: nil, engine: engine, canSwitchStreams: canSwitchStreams, onClose: onClose)
        .onAppear { speed = Double(player.defaultRate) }
    }
}
