import SharedCore
import SwiftUI

/// Shared artwork-led loading state during routing, preparation and buffering.
struct PlayerLoadingView: View {
    let context: PlaybackContext
    var coversVideo = true
    @State private var logo: UIImage?

    private var logoURL: URL? {
        let cached = MetaDetailsRepository.shared.peek(type: context.contentType, id: context.parentMetaId)
        return (context.logo ?? cached?.logo).flatMap(URL.init(string:))
    }

    var body: some View {
        ZStack {
            if coversVideo {
                Color.black.ignoresSafeArea()
                if let background = context.background ?? context.episodeStill {
                    CachedAsyncImage(string: background, contentMode: .fill) { Color.clear }
                        .ignoresSafeArea().opacity(0.22)
                }
            }
            VStack(spacing: 24) {
                // Read a warm logo synchronously when routing hands off to an engine.
                // Both fallback text and artwork occupy the same slot, so late artwork
                // cannot move the episode or loading status up and down.
                ZStack {
                    if let artwork = logo ?? ArtworkStore.cached(logoURL) {
                        Image(uiImage: artwork).resizable().scaledToFit()
                            .frame(maxWidth: 620, maxHeight: 200)
                            .accessibilityHidden(true)
                    } else {
                        Text(context.title).font(.system(size: 54, weight: .semibold))
                            .multilineTextAlignment(.center).lineLimit(3)
                            .frame(maxWidth: 900)
                    }
                }
                .frame(width: 900, height: 220)
                if let episode = context.transportSubtitle {
                    Text(episode).font(.title3).foregroundStyle(.secondary)
                }
                Text(coversVideo ? "Starting playback…" : "Buffering…")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            .padding(60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(context.title)")
        .accessibilityIdentifier("player.loading.artwork")
        // Loading identity is stationary, including inside an animated player transition.
        .transaction { $0.animation = nil }
        .task(id: logoURL) {
            guard let url = logoURL else { logo = nil; return }
            logo = ArtworkStore.cached(url)
            if logo == nil {
                let fetched = try? await ArtworkStore.fetch(url)
                guard !Task.isCancelled else { return }
                logo = fetched
            }
        }
    }
}
