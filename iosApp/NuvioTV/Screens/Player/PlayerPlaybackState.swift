import SwiftUI
import Combine

/// Shared presentation state. Each engine adapter publishes transport updates on the main thread.
@MainActor
final class PlayerPlaybackState: ObservableObject {
    @Published var positionSec: Double = 0
    @Published var durationSec: Double = 0
    @Published var isPaused: Bool = false
    @Published var isBuffering: Bool = true
    @Published var controlsVisible: Bool = false

    @Published var audioTracks: [PlayerTrack] = []
    @Published var subtitleTracks: [PlayerTrack] = []
    /// The shared bottom Settings drawer is presented.
    @Published var panelOpen: Bool = false
    @Published var requestedPanel: PlayerPanelTab = .playback
    @Published var seekableStartSec: Double = 0
    @Published var isLive = false
    private var hideTask: Task<Void, Never>?
    var detailsVisible = false
    var requestDetails: (() -> Void)?
    var openPanel: ((PlayerPanelTab) -> Void)?
    var togglePlayback: (() -> Void)?
    var seekRelative: ((Double) -> Void)?
    var revealControls: (() -> Void)?
    var hideControls: (() -> Void)?
    var performDownAction: (() -> Void)?
    /// Addon subtitle fetch in flight — the picker shows "Searching…" instead of hiding the row.
    @Published var subtitleSearchInFlight: Bool = false

    /// Active skip prompt ("Skip Intro"/"Skip Outro") when playback is inside a known segment.
    @Published var skipPrompt: SkipPrompt?

    /// Playback-settings panel state (speed, subtitle/audio delay, diagnostics).
    @Published var playbackSpeed: Double = 1.0
    @Published var subtitleDelaySec: Double = 0
    @Published var audioDelaySec: Double = 0
    @Published var streamInfo: StreamInfoSnapshot?
    /// Engine routing decision from `PlayerEngineRouter`, shown as the Stream Info "Engine" row.
    @Published var routingNote: String = ""

    /// True once playback hit end-of-file (keep-open holds the last frame; drives the post-play cover).
    @Published var isEnded: Bool = false

    /// Wired by the controller so the SwiftUI track picker can drive libmpv.
    var selectAudio: ((Int) -> Void)?
    var selectSubtitle: ((Int) -> Void)?
    var setSpeed: ((Double) -> Void)?
    var setSubtitleDelay: ((Double) -> Void)?
    var setAudioDelay: ((Double) -> Void)?
    var replay: (() -> Void)?
    var reclaimFocus: (() -> Void)?

    /// Wired by `NextEpisodeEngine`: down-press plays the ready next episode (returns true when
    /// consumed, so the skip pill doesn't also fire); backward seek cancels the countdown.
    var upNextPlayNow: (() -> Bool)?
    var upNextCancel: (() -> Void)?
    /// Menu while the up-next chip is visible dismisses the chip instead of exiting the player;
    /// returns true when it consumed the press. The next Menu exits as before (upstream 4026ec92).
    var upNextDismiss: (() -> Bool)?

    let title: String
    init(title: String) {
        self.title = title
        revealControls = { [weak self] in self?.reveal() }
        hideControls = { [weak self] in self?.hide() }
        openPanel = { [weak self] tab in
            self?.hideTask?.cancel()
            self?.requestedPanel = tab
            self?.panelOpen = true
        }
    }

    func reveal() {
        controlsVisible = true
        hideTask?.cancel()
        guard !isPaused, !isBuffering, !panelOpen else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, !self.isPaused, !self.isBuffering, !self.panelOpen else { return }
            self.controlsVisible = false
        }
    }

    func hide() { hideTask?.cancel(); controlsVisible = false }
    func closePanel() { panelOpen = false; reveal() }


    var fraction: Double {
        durationSec > seekableStartSec ? min(max((positionSec - seekableStartSec) / (durationSec - seekableStartSec), 0), 1) : 0
    }
    var hasTracks: Bool { !audioTracks.isEmpty || !subtitleTracks.isEmpty }
}
