import SwiftUI

/// Stream picker A, P3.3: "Resume from 1:12:04" / "Resume from 40 %" above the source chips
/// when the picker opened with a saved position and not "Start Over". Capsule on
/// `surfaceElevated`, `metaStrong`, non-focusable (upstream mobile's resume banner).
struct StreamPickerResumePill: View {
    let label: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "play.fill")
                .font(Theme.Font.caption)
            Text(label)
                .font(Theme.Font.metaStrong)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Palette.surfaceElevated, in: Capsule())
        .accessibilityIdentifier("stream_picker_resume_pill")
    }
}

/// The pure decisions behind the pill, pinned by `StreamPickerResumeTests`.
nonisolated enum StreamPickerResume {
    /// The pill's text, or nil when there is nothing to resume: a position wins over a fraction;
    /// a position of 10 s or less shows nothing (the players' own resume gate, `MPVPlayerView` /
    /// `PlaybackProgressRecorder.resumePositionSec`: ">10 s in and not completed"), nor does a
    /// fraction below 1 %; `startFromBeginning` hides it. Completed entries are filtered by the
    /// presenters before they get here.
    static func label(positionMs: Int64?, fraction: Double?, startFromBeginning: Bool) -> String? {
        guard !startFromBeginning else { return nil }
        if let positionMs, positionMs > 10_000 {
            return String(localized: "Resume from \(timeString(seconds: Double(positionMs) / 1_000))")
        }
        if let fraction, fraction >= 0.01, fraction < 1 {
            let percent = Int((fraction * 100).rounded())
            return String(localized: "Resume from \(String(percent) + " %")")
        }
        return nil
    }

    /// "1:12:04" with hours, "12:04" without (the player's own clock format).
    static func timeString(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
