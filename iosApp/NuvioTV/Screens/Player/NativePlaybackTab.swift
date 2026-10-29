import AVKit
import Combine
import SharedCore
import SwiftUI

/// A Playback-tab column the panel can open focused (the native transport bar's Episodes /
/// Sources menu items, P4 A8).
enum PlaybackColumn { case episodes, sources }

/// The native player's speed, kept in step with the system transport bar's speed pill (P4 D4).
/// `rate` is refreshed from `playerVC.selectedSpeed` each time the panel opens; the panel is modal
/// over the player, so the pill cannot change while the tab is visible and no KVO is needed.
@MainActor
final class NativeSpeedModel: ObservableObject {
    @Published var rate: Double = 1
    /// Set by the container: selects the matching `AVPlaybackSpeed` on the player view controller.
    var onSelect: ((Double) -> Void)?
    /// P5 B23: "Remember Speed for This Show". `rememberAvailable` is false for movies.
    @Published var remember = false
    var rememberAvailable = false
    var showId: String?
    var onRememberChange: ((Bool) -> Void)?

    func select(_ value: Double) { onSelect?(value) }

    /// Saves `rate` under the show when Remember is on (no-op otherwise).
    func saveIfRemembered(rate: Double) {
        guard remember, let showId else { return }
        PlayerTrackPreferenceStorage.shared.savePlaybackSpeed(parentMetaId: showId, speed: rate)
    }

    /// Applies `value` through `AVPlayerViewController.selectSpeed(_:)` (so the system pill
    /// agrees) and makes the live rate follow while playing [C-16]: `selectedSpeed` mirrors
    /// `player.defaultRate`, not the live `rate`.
    static func apply(_ value: Double, on playerVC: AVPlayerViewController, model: NativeSpeedModel) {
        guard let match = playerVC.speeds.first(where: { abs(Double($0.rate) - value) < 0.001 }) else {
            print("[NativePlayer] speed → \(value) (tab) not in the player's speed list")
            return
        }
        playerVC.selectSpeed(match)
        model.rate = Double(match.rate)
        var fixed = false
        if let player = playerVC.player, player.timeControlStatus != .paused, player.rate != match.rate {
            player.rate = match.rate
            fixed = true
        }
        print("[NativePlayer] speed → \(String(format: "%g", value)) (tab)\(fixed ? " rateFixed=1" : "")")
    }
}

/// The native player's "Playback" panel tab: the speed row, then the Episodes and Sources columns
/// shared with the mpv tab (`PlayerPlaybackColumns.swift`). No audio delay (AVPlayer has no audio
/// offset) and no Diagnostics toggle (the Info tab carries the stream rows) — spec D2/D3.
struct NativePlaybackTab: View {
    @ObservedObject var engine: NextEpisodeEngine
    @ObservedObject var speed: NativeSpeedModel
    let canSwitchStreams: Bool
    /// The column the transport bar's menu item asked for; nil = the panel's normal tab-row focus.
    let initialColumn: PlaybackColumn?
    let onClose: () -> Void

    @FocusState private var episodesFirst: Bool
    @FocusState private var sourcesFirst: Bool
    /// The initial-column focus move has happened (or been given up on).
    @State private var focusPlaced = false

    private var showsEpisodes: Bool {
        canSwitchStreams && !PlayerEpisodesColumn.sortedEpisodes(engine).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                PlayerPanelSectionCaption(text: String(localized: "Playback Speed"))
                PlayerSpeedRow(current: speed.rate) { speed.select($0) }
                if speed.rememberAvailable {
                    PlayerRememberSpeedRow(isOn: speed.remember) { speed.onRememberChange?(!speed.remember) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
            if showsEpisodes {
                PlayerEpisodesColumn(engine: engine, onClose: onClose, firstRowFocus: $episodesFirst)
                    .frame(width: 440)
                    .focusSection()
            }
            if canSwitchStreams {
                PlayerSourcesColumn(engine: engine, onClose: onClose, firstRowFocus: $sourcesFirst)
                    .frame(width: 560)
                    .focusSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 520, alignment: .topLeading)
        .onAppear {
            // After the panel's own onAppear has put focus on the tab row.
            guard initialColumn != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { placeInitialFocus() }
        }
        .onChange(of: engine.sources.isEmpty) { _, isEmpty in
            // The Sources list loads after the tab appears: move in once its first row exists.
            if !isEmpty, initialColumn == .sources, !focusPlaced { placeInitialFocus() }
        }
    }

    private func placeInitialFocus() {
        switch initialColumn {
        case .episodes where showsEpisodes:
            focusPlaced = true
            episodesFirst = true
        case .sources where canSwitchStreams && !engine.sources.isEmpty:
            focusPlaced = true
            sourcesFirst = true
        default:
            break
        }
    }
}
