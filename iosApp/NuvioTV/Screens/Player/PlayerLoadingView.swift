import SharedCore
import SwiftUI

/// Shared artwork-led loading state during routing, preparation and buffering.
struct PlayerLoadingView: View {
    let context: PlaybackContext
    var coversVideo = true
    @State private var logo: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

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
                if let logo {
                    Image(uiImage: logo).resizable().scaledToFit()
                        .frame(maxWidth: 620, maxHeight: 200)
                        .accessibilityHidden(true)
                } else {
                    Text(context.title).font(.system(size: 54, weight: .semibold))
                        .multilineTextAlignment(.center).lineLimit(3)
                        .frame(maxWidth: 900)
                }
                if let episode = context.transportSubtitle {
                    Text(episode).font(.title3).foregroundStyle(.secondary)
                }
                Text(coversVideo ? "Starting playback…" : "Buffering…")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            .opacity(reduceMotion ? 1 : (breathing ? 1 : 0.65))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathing)
            .padding(60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(context.title)")
        .accessibilityIdentifier("player.loading.artwork")
        .onAppear { breathing = true }
        .task(id: logoURL) {
            guard let url = logoURL else { logo = nil; return }
            logo = ArtworkStore.cached(url)
            if logo == nil { logo = try? await ArtworkStore.fetch(url) }
        }
    }
}
