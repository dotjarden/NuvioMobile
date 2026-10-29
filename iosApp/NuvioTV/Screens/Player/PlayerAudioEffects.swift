import Foundation

/// mpv audio effects (P5 B20). "Dialogue" is the only mode besides Off: this MPVKit's libavfilter
/// ships no `dynaudnorm` / `loudnorm` / compressor, so a Night mode cannot be built. A Night mode
/// would be one more case here plus one more branch in `PlayerAudioEffects.afValue`.
enum PlayerAudioMode: String, CaseIterable, Equatable {
    case off
    case dialogue
}

struct PlayerAudioEffectsState: Equatable {
    var boostDb: Int
    var mode: PlayerAudioMode
}

enum PlayerAudioEffects {
    static let boostStepsDb = [0, 2, 4, 6, 8, 10]
    /// mpv `volume-max`: +10 dB is 316 %, so the property must be allowed past 200.
    static let volumeMax = 320
    /// Layouts whose FFmpeg channel order puts the centre channel (FC) at c2.
    static let centreLayouts: Set<String> = ["5.1", "5.1(side)", "7.1"]
    /// The `af` filter label, so the app owns exactly one named entry.
    static let dialogueLabel = "nuvio-dialogue"

    static func storedState(_ d: UserDefaults = .standard) -> PlayerAudioEffectsState {
        PlayerAudioEffectsState(
            boostDb: clampBoost(d.integer(forKey: PlayerTuning.boostDbKey)),
            mode: PlayerAudioMode(rawValue: d.string(forKey: PlayerTuning.audioModeKey) ?? "") ?? .off
        )
    }

    /// Clamped to 0...10 and snapped down to an even step.
    static func clampBoost(_ db: Int) -> Int {
        let clamped = min(10, max(0, db))
        return clamped - (clamped % 2)
    }

    /// 100 × 10^(dB/20): 0 → 100, 6 → 199.53, 10 → 316.23.
    static func volumePercent(boostDb: Int) -> Double {
        100.0 * pow(10.0, Double(boostDb) / 20.0)
    }

    /// The full `af` value. Off → "". Dialogue on a centre layout lifts the centre channel by
    /// 1.5×; anything else (stereo, mono, unknown) gets a gentle presence boost instead.
    static func afValue(mode: PlayerAudioMode, channels: String?, channelCount: Int) -> String {
        switch mode {
        case .off:
            return ""
        case .dialogue:
            if let layout = channels, centreLayouts.contains(layout), channelCount >= 6 {
                let maps = (0..<channelCount).map { $0 == 2 ? "c2=1.5*c2" : "c\($0)=c\($0)" }
                return "@\(dialogueLabel):lavfi=[pan=\(layout)|\(maps.joined(separator: "|"))]"
            }
            return "@\(dialogueLabel):lavfi=[equalizer=f=2500:t=q:w=1.0:g=4]"
        }
    }
}
