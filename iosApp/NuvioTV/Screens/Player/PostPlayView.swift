import Combine
import SharedCore
import SwiftUI

/// Post-play screen shown when playback reaches the end without an autoplay hand-off
/// (Android TV `PostPlayOverlay` parity): replay or exit, plus (P5 B22) a More Like This row
/// when the presenter can push a Detail page (`onOpenTitle` set).
///
/// Shared by both engines: `MPVPlayerScreen` and `NativePlayerScreen` present it in a
/// `fullScreenCover` when the item ends and no Up Next hand-off is pending.
struct PostPlayView: View {
    let title: String
    let poster: String?
    let onReplay: () -> Void
    let onExit: () -> Void
    /// More Like This titles (already filtered by `PostPlayMoreLikeThis.filter`).
    var moreLikeThis: [MetaPreview] = []
    /// A poster was selected: the presenter stores the title and navigates AFTER its cover
    /// dismisses. nil = this launch path cannot push a page, so no row is shown.
    var onOpenTitle: ((MetaPreview) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var showsRow: Bool { onOpenTitle != nil && !moreLikeThis.isEmpty }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .center, spacing: 48) {
                    if let poster, !poster.isEmpty {
                        CachedAsyncImage(string: poster)
                            .frame(width: showsRow ? 200 : 260, height: showsRow ? 300 : 390)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        Text("That's the end of")
                            .font(Theme.Font.screenTitle.weight(.regular))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(title)
                            .font(Theme.Font.hero)
                            .foregroundStyle(.white)
                            .lineLimit(showsRow ? 2 : 3)
                            .frame(maxWidth: 800, alignment: .leading)

                        Button {
                            dismiss()
                            onReplay()
                        } label: {
                            Label("Play Again", systemImage: "arrow.counterclockwise")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("postplay.replay")

                        Button {
                            // Dismissing the player screen tears the cover down with it —
                            // don't also dismiss the cover (competing transitions).
                            onExit()
                        } label: {
                            Label("Back to Details", systemImage: "chevron.backward")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("postplay.back")
                    }
                }

                if showsRow, let onOpenTitle {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("More Like This")
                            .font(Theme.Font.sectionTitle)
                            .foregroundStyle(.white.opacity(0.85))
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: Theme.Spacing.lg) {
                                ForEach(Array(moreLikeThis.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        // Store the title first, then close the player. The
                                        // presenter navigates from its cover's onDismiss.
                                        onOpenTitle(item)
                                        onExit()
                                    } label: {
                                        PosterCard(
                                            title: item.name,
                                            imageURL: item.poster,
                                            fallbackImageURL: item.rawPosterUrl,
                                            width: Theme.Size.miniPosterWidth,
                                            height: Theme.Size.miniPosterHeight
                                        )
                                    }
                                    .cardFocusButtonStyle()
                                    .posterButtonShape()
                                    .accessibilityIdentifier("postplay.moreLikeThis.\(index)")
                                }
                            }
                            .padding(.vertical, Theme.Spacing.md)
                        }
                        .scrollClipDisabled()
                        .focusSection()
                    }
                }
            }
            .padding(80)
        }
    }
}

/// Pure list shaping for the post-play More Like This row.
enum PostPlayMoreLikeThis {
    static let cap = 12

    /// Drops the current title and duplicate ids, keeps source order, caps at `cap`.
    static func filter(_ items: [MetaPreview], excludingId: String, cap: Int = PostPlayMoreLikeThis.cap) -> [MetaPreview] {
        var seen = Set<String>([excludingId])
        var out: [MetaPreview] = []
        for item in items where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
            if out.count >= cap { break }
        }
        return out
    }
}

/// Loads the post-play row from the same source Detail's More Like This uses (D4), without
/// touching the Detail singleton's UI state. Errors give an empty row.
@MainActor
final class PostPlayMoreLikeThisLoader: ObservableObject {
    @Published private(set) var items: [MetaPreview] = []
    private var loadedKey: String?

    func load(type: String, id: String) {
        let key = "\(type):\(id)"
        guard loadedKey != key else { return }
        loadedKey = key
        #if DEBUG
        let stubCount = UserDefaults.standard.integer(forKey: "debug.postPlayStubTitles")
        if stubCount > 0 {
            items = (1...stubCount).map { Self.stub($0) }
            return
        }
        #endif
        Task { [weak self] in
            let raw = (try? await MetaDetailsRepository.shared.moreLikeThisChecked(type: type, id: id)) ?? []
            self?.items = PostPlayMoreLikeThis.filter(raw, excludingId: id)
        }
    }

    #if DEBUG
    private static func stub(_ n: Int) -> MetaPreview {
        MetaPreview(
            id: "stub-\(n)", type: "movie", name: "Stub \(n)", poster: nil, banner: nil, logo: nil,
            posterShape: PosterShape.poster, description: nil, releaseInfo: nil, rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: nil, genres: [], rawPosterUrl: nil,
            landscapePoster: nil, rawLandscapePosterUrl: nil, customPosterApplied: false
        )
    }
    #endif
}
