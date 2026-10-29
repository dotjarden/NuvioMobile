import SwiftUI
import SharedCore

/// Stream picker A, P1 (`docs/stream-picker-addons-plan-2026-10-25.md` §2): the full-bleed art
/// behind the two panes. Only drawn in the Cinematic background mode (Settings › Sources › Source
/// Background, Cinematic by default on tvOS since decision D1); Normal keeps the plain app
/// background, today's look.
///
/// The image is decoded once at a 1280 px long side (it sits under a scrim, so screen resolution
/// buys nothing and would pin a ~33 MB bitmap per open picker) and released while the picker is
/// off screen. No live `.blur`: the scrim does the softening (P4.2, the same reason Detail dropped
/// Liquid Glass).
struct StreamPickerBackdrop: View {
    let mode: StreamBackgroundMode
    let imageURL: String?
    let fallbackURL: String?

    /// Long side of the decode, in pixels (the panel material and the scrim hide the rest).
    nonisolated static let decodeLongSidePixels = 1280

    var body: some View {
        ZStack {
            Theme.Palette.background
            if mode == .cinematic, let imageURL, !imageURL.isEmpty {
                GeometryReader { geo in
                    // Review r1 (P3): no shimmer under the material while the fan-out runs, and no
                    // film glyph in the open middle of the scrim when the art fails: plain background.
                    CachedAsyncImage(
                        string: imageURL,
                        fallback: fallbackURL,
                        decodeSize: .pixels(Self.decodeLongSidePixels),
                        releasesWhenHidden: true,
                        loading: { Color.clear },
                        failure: { Color.clear }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
                StreamPickerScrim()
            }
        }
        .ignoresSafeArea()
        // Decorative: the info panel's logo and lines carry the title for VoiceOver.
        .accessibilityHidden(true)
    }

    /// Which art the backdrop shows: the episode still when there is one (the fallback is then the
    /// title's backdrop), else the title's backdrop as given, else the poster. Deliberately NOT
    /// Detail's larger-rendition chain (`DetailBackdropURL.upgraded`): a 1280 px decode under a
    /// scrim gains nothing from a multi-MB `original`, which a Home or deep-link open would have to
    /// download. `nonisolated` so `StreamPickerLayoutTests` can pin it without a view host.
    nonisolated static func plan(
        episodeStill: String?,
        background: String?,
        poster: String?
    ) -> (primary: String?, fallback: String?) {
        func nonEmpty(_ value: String?) -> String? { (value ?? "").isEmpty ? nil : value }
        let art = nonEmpty(background) ?? nonEmpty(poster)
        if let still = nonEmpty(episodeStill) {
            return (still, art)
        }
        return (art, nil)
    }
}

/// The scrim over the backdrop: solid app background at both screen edges, open in the middle
/// (Android TV's `StreamScreen` horizontal stops), plus a band that fades the bottom so the list's
/// last rows and the info panel's progress line read. App background colour, not black, so the
/// White theme gets a light scrim.
struct StreamPickerScrim: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: StreamPickerScrimStops.horizontal.map {
                    .init(color: Theme.Palette.background.opacity($0.opacity), location: $0.location)
                },
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                stops: StreamPickerScrimStops.vertical.map {
                    .init(color: Theme.Palette.background.opacity($0.opacity), location: $0.location)
                },
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// The scrim's stops as plain numbers, so a unit test can pin them.
nonisolated enum StreamPickerScrimStops {
    struct Stop: Equatable {
        let location: CGFloat
        let opacity: Double
    }

    /// Leading → trailing: 1.0, 0.85, 0.40, 0.15, 0.40, 0.85, 1.0.
    static let horizontal: [Stop] = [
        Stop(location: 0.00, opacity: 1.00),
        Stop(location: 0.15, opacity: 0.85),
        Stop(location: 0.30, opacity: 0.40),
        Stop(location: 0.50, opacity: 0.15),
        Stop(location: 0.70, opacity: 0.40),
        Stop(location: 0.85, opacity: 0.85),
        Stop(location: 1.00, opacity: 1.00),
    ]

    /// Top → bottom: clear until 55 %, then to 0.6 at the bottom edge.
    static let vertical: [Stop] = [
        Stop(location: 0.00, opacity: 0.00),
        Stop(location: 0.55, opacity: 0.00),
        Stop(location: 1.00, opacity: 0.60),
    ]
}
