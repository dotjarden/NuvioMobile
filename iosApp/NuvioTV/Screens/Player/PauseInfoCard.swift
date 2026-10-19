import SwiftUI

/// Metadata card shown top-leading after playback has been paused for a moment: artwork, title,
/// episode line, stream/source info, and time remaining (Android TV `PauseOverlay` parity).
/// Shared by both engines: mpv passes `state.positionSec` / `state.durationSec`, native passes
/// the coordinator's position and duration.
struct PauseInfoCard: View {
    let context: PlaybackContext
    let positionSec: Double
    let durationSec: Double

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            if let poster = context.poster, !poster.isEmpty {
                CachedAsyncImage(string: poster)
                    .frame(width: 140, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Paused")
                    .font(Theme.Font.meta)
                    .foregroundStyle(.white.opacity(0.7))
                Text(context.title)
                    .font(Theme.Font.screenTitle)
                    .lineLimit(2)
                if let season = context.season, let episode = context.episode {
                    Text("Season \(season) \u{00B7} Episode \(episode)")
                        .font(Theme.Font.body)
                        .foregroundStyle(.white.opacity(0.85))
                }
                if durationSec > 0 {
                    Text("\(remainingString) remaining")
                        .font(Theme.Font.body).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let provider = context.providerName, !provider.isEmpty {
                    Text(provider)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 860, alignment: .leading)
        // BUG-180 (Steven rc7): solid player surface, not glass + shadow (see PlayerSurfaceStyle).
        .playerSurface(in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("player.pauseCard")
    }

    private var remainingString: String {
        let total = Int(max(durationSec - positionSec, 0))
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
