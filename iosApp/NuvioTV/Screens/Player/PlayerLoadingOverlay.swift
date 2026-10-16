import Combine
import SharedCore
import SwiftUI

// P4 B24: the loading screen both engines and the router draw while a video starts — the poster,
// the title and what the player is doing — instead of a bare spinner. The stage enum lives in
// `PlaybackModels.swift` (agent B, so the native coordinator can publish it); this file holds the
// views, the status copy, the mpv stage reducer and the DEBUG history the UI legs read.
// Spec: docs/research/player-p4-spec-native-parity.md §8.1–8.3.

extension PlayerLoadingStage {
    /// The status line under the title. `.started` renders nothing (the overlay is fading out).
    var statusText: String {
        switch self {
        case .checking: String(localized: "Checking the stream\u{2026}")
        case .connecting: String(localized: "Connecting\u{2026}")
        // The two existing `NativePreparingLabel` strings, reused.
        case .preparing(let dv): dv ? String(localized: "Preparing Dolby Vision\u{2026}")
                                    : String(localized: "Preparing playback\u{2026}")
        case .subtitles: String(localized: "Loading subtitles\u{2026}")
        case .buffering(nil): String(localized: "Buffering\u{2026}")
        case .buffering(let p?): String(localized: "Buffering \(p) %")
        case .started: ""
        }
    }

    /// The overlay's accessibility value and the DEBUG history token.
    var debugName: String { logToken }

    var isStarted: Bool { if case .started = self { true } else { false } }
}

/// Settings › Playback › Loading Screen (`PlayerSettingsUiState.showLoadingOverlay`, shared and
/// synced as `show_loading_overlay`; default on). Read synchronously so a screen can seed its
/// `@State` in `init` — reading it in `onAppear` would flash the overlay for one frame when it is
/// off (critique C17).
enum PlayerLoadingOverlaySetting {
    static var enabled: Bool {
        // A cold launch straight into a player (Top Shelf, the smoke rig) can get here before
        // anything else hydrated the repository; `ensureLoaded` is a no-op once it has.
        PlayerSettingsRepository.shared.ensureLoaded()
        return (PlayerSettingsRepository.shared.uiState.value_ as? PlayerSettingsUiState)?.showLoadingOverlay != false
    }
}

struct PlayerLoadingOverlay: View {
    let context: PlaybackContext
    let stage: PlayerLoadingStage

    var body: some View {
        ZStack {
            Color.black
            if let background = context.background, !background.isEmpty {
                CachedAsyncImage(string: background)
                    .opacity(0.28)
                    .blur(radius: 30)
                    .clipped()
            }
            HStack(alignment: .center, spacing: 48) {
                if let poster = context.poster, !poster.isEmpty {
                    CachedAsyncImage(string: poster)
                        .frame(width: 260, height: 390)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(context.title)
                        .font(Theme.Font.screenTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let subtitle = NativeInfoHeader(context: context).subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Font.body)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    HStack(spacing: 16) {
                        ProgressView()
                        Text(stage.statusText)
                            .font(Theme.Font.body).monospacedDigit()
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .padding(.top, 10)
                }
            }
            .frame(maxWidth: 1200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .focusable(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.loadingOverlay")
        .accessibilityValue(stage.debugName)
        #if DEBUG
        // A fast start can come and go between two XCUITest snapshots; the history label keeps
        // the stage the overlay was first drawn at.
        .onAppear { PlayerLoadingHistory.shared.noteOverlayDrawn(stage, contextID: context.id) }
        #endif
    }
}

/// The plain spinner each site drew before B24; the setting-off branch keeps it.
struct PlayerLoadingSpinner: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView().scaleEffect(1.5)
        }
    }
}

/// mpv's startup stages (spec §8.1). Main thread, pure, so `PlayerLoadingStageTests` drives it.
///
/// `.connecting` until `MPV_EVENT_FILE_LOADED`, then `.buffering(percent:)` until the first
/// `MPV_EVENT_PLAYBACK_RESTART` that completes the resume seek — or any restart after FILE_LOADED
/// when no resume seek was issued. A restart before the resume seek (mpv's own start of playback)
/// does not count. Backstop: the position advancing by more than 1 s while not paused. Once
/// `.started`, it never moves back: a mid-play rebuffer is the small spinner's job, not this one.
struct MPVStartupStageReducer: Equatable {
    private(set) var stage: PlayerLoadingStage = .connecting
    private var fileLoaded = false
    /// The resume seek's generation (nil = no resume seek this file).
    private var resumeGeneration: Int?
    /// First position seen once loaded and playing (the backstop's baseline).
    private var baselineSec: Double?

    var started: Bool { stage.isStarted }

    /// FILE_LOADED, with the generation of the resume seek it just issued (nil = none).
    @discardableResult
    mutating func fileLoaded(resumeGeneration: Int?) -> Bool {
        guard !started, !fileLoaded else { return false }
        fileLoaded = true
        self.resumeGeneration = resumeGeneration
        return set(.buffering(percent: nil))
    }

    /// A PLAYBACK_RESTART. `completesSeek` is the app seek generation it confirms (nil when it is
    /// not the completion of one of our seeks).
    @discardableResult
    mutating func playbackRestart(completesSeek: Int?) -> Bool {
        guard fileLoaded, !started else { return false }
        if let resumeGeneration {
            guard let completesSeek, completesSeek >= resumeGeneration else { return false }
        }
        return set(.started)
    }

    /// `cache-buffering-state` (0–100) while buffering before start.
    @discardableResult
    mutating func bufferingPercent(_ percent: Int?) -> Bool {
        guard fileLoaded, !started else { return false }
        return set(.buffering(percent: percent.map { min(max($0, 0), 100) }))
    }

    /// The UI tick: the position-advance backstop.
    @discardableResult
    mutating func tick(positionSec: Double, paused: Bool) -> Bool {
        guard fileLoaded, !started, positionSec.isFinite else { return false }
        if paused { baselineSec = nil; return false }
        guard let base = baselineSec else { baselineSec = positionSec; return false }
        return positionSec - base > 1 ? set(.started) : false
    }

    private mutating func set(_ next: PlayerLoadingStage) -> Bool {
        guard next != stage else { return false }
        stage = next
        return true
    }
}

#if DEBUG
/// The DEBUG oracle for the B24 legs (critique C9): each screen appends every stage it shows, so
/// `checking>connecting>…>started` survives stages too short for XCUITest polling. Keyed on the
/// context id: the first note for a new context starts a new history.
@MainActor
final class PlayerLoadingHistory: ObservableObject {
    static let shared = PlayerLoadingHistory()
    @Published private(set) var text = ""
    /// The stage the loading overlay was first drawn at for this context (nil = never drawn).
    @Published private(set) var overlayDrawnAt: String?
    private var contextID: String?
    private var last: String?

    private func begin(_ id: String) {
        guard id != contextID else { return }
        contextID = id; text = ""; last = nil; overlayDrawnAt = nil
    }

    func noteOverlayDrawn(_ stage: PlayerLoadingStage, contextID id: String) {
        begin(id)
        if overlayDrawnAt == nil { overlayDrawnAt = stage.logToken }
    }

    func note(_ stage: PlayerLoadingStage, contextID id: String) {
        begin(id)
        // `buffering(42)` and `buffering` are one stage for the history.
        let token = stage.logToken.split(separator: "(").first.map(String.init) ?? stage.logToken
        guard token != last else { return }
        last = token
        text = text.isEmpty ? token : text + ">" + token
    }
}

struct PlayerLoadingHistoryLabel: View {
    @ObservedObject private var history = PlayerLoadingHistory.shared

    var body: some View {
        // `<stage>>…>started overlay=<first drawn stage | none>`
        Text(verbatim: (history.text.isEmpty ? "none" : history.text) + " overlay=" + (history.overlayDrawnAt ?? "none"))
            .font(.system(size: 8))
            .opacity(0.011)
            .accessibilityIdentifier("debug_loadingHistory")
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
#endif
