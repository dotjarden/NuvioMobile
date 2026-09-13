import SwiftUI

/// The only tvOS transport UI. Renderers supply state and commands, never controls.
struct PlayerChrome: View {
    @ObservedObject var state: PlayerPlaybackState
    let context: PlaybackContext
    let panelModel: PlayerTopPanelModel
    let extraTab: PlayerPanelExtraTab
    let onExit: () -> Void
    @FocusState private var videoFocused: Bool
    @FocusState private var transportFocus: PlayerTransportFocus?
    @State private var systemSession: PlayerSystemSession?
    @State private var revealFocus: PlayerTransportFocus = .timeline

    var body: some View {
        ZStack(alignment: .bottom) {
            // SwiftUI owns focus while its controls are hidden. Merely making the sibling
            // UIKit renderer first responder does not give it tvOS directional focus.
            if !state.controlsVisible && !state.panelOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($videoFocused)
                    .accessibilityLabel("Video")
                    .accessibilityIdentifier("player.videoSurface")
                    .onTapGesture { state.togglePlayback?() }
                    .onMoveCommand { direction in
                        switch direction {
                        case .left: state.seekRelative?(-10)
                        case .right: state.seekRelative?(10)
                        case .up:
                            revealFocus = .settings
                            state.revealControls?()
                        case .down:
                            state.performDownAction?()
                        default: break
                        }
                    }
            }

            if state.isBuffering {
                PlayerLoadingView(context: context, coversVideo: state.positionSec < 1)
                    .allowsHitTesting(false)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.65), .black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .opacity(state.controlsVisible && !state.panelOpen ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.25), value: state.controlsVisible)

            // Remove hidden controls from the focus tree. tvOS glass buttons can otherwise
            // remain exposed to focus/accessibility when their container only changes opacity.
            if state.controlsVisible && !state.panelOpen {
                PlayerControlsOverlay(state: state, subtitle: context.transportSubtitle, focus: $transportFocus)
                    .transition(.opacity)
            }

            if state.panelOpen {
                PlayerTopPanel(model: panelModel, extraTab: extraTab, initialTab: state.requestedPanel)
                    .id(state.requestedPanel)
                    .accessibilityAddTraits(.isModal)
                    .focusSection()
            }
        }
        .onChange(of: state.controlsVisible) { _, visible in
            videoFocused = !visible && !state.panelOpen
            if visible {
                let target = revealFocus
                revealFocus = .timeline
                // Re-enable the controls before moving focus from the hidden-video surface.
                DispatchQueue.main.async {
                    if state.controlsVisible && !state.panelOpen { transportFocus = target }
                }
            }
            if !visible { transportFocus = nil }
        }
        .onChange(of: state.panelOpen) { _, open in
            videoFocused = !open && !state.controlsVisible
            transportFocus = nil
            if !open {
                DispatchQueue.main.async {
                    if !state.panelOpen && state.controlsVisible { transportFocus = .timeline }
                }
            }
        }
        .onExitCommand {
            if state.panelOpen { state.closePanel() }
            else if state.controlsVisible { state.hideControls?() }
            else if state.upNextDismiss?() != true { onExit() }
        }
        .onPlayPauseCommand { state.togglePlayback?() }

        .onAppear {
            systemSession = PlayerSystemSession(state: state, context: context)
            UIApplication.shared.isIdleTimerDisabled = !state.isPaused
            state.isLive = context.isLive
            panelModel.onClose = { [weak state] in state?.closePanel() }
            state.reveal()
        }
        .onChange(of: state.isBuffering) { _, _ in
            if state.controlsVisible { state.reveal() }
        }
        .onChange(of: state.isPaused) { _, paused in
            UIApplication.shared.isIdleTimerDisabled = !paused
            state.reveal()
        }
        .onDisappear {
            systemSession?.stop()
            systemSession = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

private enum PlayerTransportFocus: Hashable { case timeline, settings, subtitles, audio }

/// Native-style action row above the scrubber; elapsed and remaining time sit below it.
private struct PlayerControlsOverlay: View {
    @ObservedObject var state: PlayerPlaybackState
    let subtitle: String?
    var focus: FocusState<PlayerTransportFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    if let subtitle { Text(subtitle).font(.system(size: 26)).foregroundStyle(.secondary).lineLimit(1) }
                    Text(state.title).font(.system(size: 52, weight: .semibold)).lineLimit(1)
                        .accessibilityIdentifier("player.transport.title")
                }
                Spacer(minLength: 24)
                GlassEffectContainer(spacing: 24) {
                    HStack(spacing: 24) {
                        Button { state.openPanel?(.playback) } label: { transportIcon("slider.horizontal.3") }
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("player.settings")
                            .focused(focus, equals: .settings)
                            .onMoveCommand { move(from: .settings, direction: $0) }
                        Button { state.openPanel?(.subtitles) } label: { transportIcon("captions.bubble") }
                            .accessibilityLabel("Subtitles")
                            .accessibilityIdentifier("player.subtitles")
                            .focused(focus, equals: .subtitles)
                            .onMoveCommand { move(from: .subtitles, direction: $0) }
                        Button { state.openPanel?(.audio) } label: { transportIcon("waveform") }
                            .accessibilityLabel("Audio")
                            .accessibilityIdentifier("player.audio")
                            .focused(focus, equals: .audio)
                            .onMoveCommand { move(from: .audio, direction: $0) }
                    }
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)

            VStack(spacing: 8) {
                ProgressBar(fraction: state.fraction)
                    .frame(height: focus.wrappedValue == .timeline ? 12 : 8)
                HStack(spacing: 12) {
                    Text(state.isLive ? "LIVE" : timeString(state.positionSec))
                    Image(systemName: state.isPaused ? "pause.circle" : "play.circle")
                    Spacer()
                    Text(state.isLive && state.durationSec == 0 ? "" : "-\(timeString(max(state.durationSec - state.positionSec, 0)))")
                }
                .font(Theme.Font.caption).monospacedDigit()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .focusable()
            .focused(focus, equals: .timeline)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("player.timeline")
            .accessibilityLabel(state.isPaused ? "Paused, playback position" : "Playing, playback position")
            .accessibilityValue(timeString(state.positionSec))
            .accessibilityHint("Press Left or Right to seek ten seconds. Press Up for controls. Press Select to play or pause.")
            .onTapGesture { state.togglePlayback?() }
            .onMoveCommand { direction in
                if direction == .left { state.seekRelative?(-10) }
                if direction == .right { state.seekRelative?(10) }
                if direction == .up { state.revealControls?(); focus.wrappedValue = .settings }
                if direction == .down { state.performDownAction?() }
            }
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 118)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }

    private func transportIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 26)).frame(width: 46, height: 46)
    }

    private func move(from current: PlayerTransportFocus, direction: MoveCommandDirection) {
        state.revealControls?()
        let actions: [PlayerTransportFocus] = [.settings, .subtitles, .audio]
        guard let index = actions.firstIndex(of: current) else { return }
        switch direction {
        case .left: focus.wrappedValue = actions[max(0, index - 1)]
        case .right: focus.wrappedValue = actions[min(actions.count - 1, index + 1)]
        case .down: focus.wrappedValue = .timeline
        default: break
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
    }
}
