import SwiftUI

/// BUG-177 (Steven rc7, 2026-10-18: "the focus ring and the depth effect don't apply to the
/// trailers, the episodes and the season posters"). The three Detail tiles — `TrailerThumbCard`,
/// `EpisodeThumbCard`, `SeasonPosterCard` — were the last labels on `TileFocusLift` +
/// `cardFocusButtonStyle(lift: .plain)`, which never reads the accent ring (the BUG-104 follow-up
/// documented on `CardButtonLift`). This is `CastCard`/`FolderTile`'s architecture (BUG-102/108)
/// factored once for all three, so the three cannot drift:
///
/// - ring ON: the `ringWidth` band is reserved by a static, never-focus-linked shrink of the
///   artwork, `PlainLabelRing` draws the ring in the vacated band (accent, or the poster's colour
///   with "Focus Ring Takes Poster Color"), and the tile owns its lift (`PlainLabelRing.lift`:
///   `.manualScale` with zoom on, a no-op with No Zoom) so ring and picture are one SwiftUI layer.
///   The call site uses the default `cardFocusButtonStyle()` (`.card`), which swaps `.borderless`
///   for `RingCardButtonStyle` in exactly that cell (`CardButtonStyleKind.resolve`).
/// - ring OFF: byte-for-byte the old `TileFocusLift` (system highlight with zoom on, still border
///   + shadow with No Zoom), and `CardButtonStyleKind` still resolves `.borderless`/`.still` for a
///   `.card` call site, so both ring-off looks are unchanged.
///
/// Focus truth is `@Environment(\.isFocused)`, the same value the tiles' captions already read.
/// It installs no `.focused` binding, so it cannot collide with the rows' own `FocusState`s (the
/// Codex 2026-08-29 collision `CastCard`'s `stillFocused` parameter exists for).
enum DetailTileFocus {
    /// Whether the tile takes the ring architecture (true) or keeps `TileFocusLift` (false).
    static func drawsOwnRing(accentFocusRing: Bool) -> Bool { accentFocusRing }

    // The tiles' captions drop by `CardFocusMode.resolve(...)` (`CardCaptionFocusDrop`): 20 pt in
    // both zoom-on modes, 0 with No Zoom, so the caption follows ring mode's manual lift too.

    /// Per-axis shrink that reserves the `ringWidth` band on every edge of a `length`-long side.
    /// 1 (no shrink) for a degenerate side, as `TileFocusLift`'s measured fallback.
    static func bandScale(_ length: CGFloat) -> CGFloat {
        length > 0 ? max(0, length - 2 * ringWidth) / length : 1
    }

    /// BUG-177: "Depth Takes Poster Color" for these tiles — sample only when the toggle is on, the
    /// depth effect draws for the tile's surface, and there is a real picture to sample.
    static func samplesRailColor(depthTakesPosterColor: Bool, depthEnabled: Bool, artworkURL: String?) -> Bool {
        guard depthTakesPosterColor, depthEnabled, let artworkURL else { return false }
        return !artworkURL.isEmpty
    }
}

/// See `DetailTileFocus`. Attach where `tileFocusLift(cornerRadius:)` sat: on the artwork
/// container, after its fixed `.frame`, outside its clip and depth layer.
struct DetailTileFocusLift: ViewModifier {
    @Environment(\.focusAppearance) private var focusAppearance
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cornerRadius: CGFloat
    /// The artwork's fixed size (the container's own `.frame`): the band and the lift's scale are
    /// derived from it, so no measurement pass is needed.
    let size: CGSize
    /// The art the ring may take its colour from ("Focus Ring Takes Poster Color"); nil = never.
    var tintSource: String? = nil

    /// FEAT-46 parity with `FolderTile`: the last ring colour the store answered for this tile.
    @State private var posterRingTint: Color?

    private var samplesRingColor: Bool {
        focusAppearance.ringTakesPosterColor && !(tintSource ?? "").isEmpty
    }

    private var ringTint: Color? {
        guard samplesRingColor, isFocused else { return nil }
        return ArtworkColorStore.shared.cachedColor(for: [tintSource]) ?? posterRingTint
    }

    func body(content: Content) -> some View {
        let accent = focusAppearance.accentFocusRing
        let noZoom = focusAppearance.noZoomOnFocus
        if DetailTileFocus.drawsOwnRing(accentFocusRing: accent) {
            content
                .scaleEffect(x: DetailTileFocus.bandScale(size.width),
                             y: DetailTileFocus.bandScale(size.height))
                .overlay {
                    if let ring = PlainLabelRing.resolve(accentFocusRing: accent,
                                                         noZoomOnFocus: noZoom,
                                                         focused: isFocused) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(ringTint ?? ring.color, lineWidth: ringWidth)
                    }
                }
                // Outermost of the pair so ring, band, depth rail and picture scale as one layer
                // (BUG-108's rule on `FolderTile`).
                .modifier(CardArtworkFocusLift(
                    mode: PlainLabelRing.lift(accentFocusRing: accent, noZoomOnFocus: noZoom),
                    isFocused: isFocused,
                    artworkHeight: size.height,
                    cornerRadius: cornerRadius
                ))
                .onChange(of: isFocused, initial: true) { _, focused in
                    guard focused, samplesRingColor else { return }
                    ArtworkColorStore.shared.color(for: [tintSource]) { color in
                        guard posterRingTint != color else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { posterRingTint = color }
                    }
                }
        } else {
            content.tileFocusLift(cornerRadius: cornerRadius)
        }
    }
}

extension View {
    /// BUG-177: see `DetailTileFocusLift`.
    func detailTileFocusLift(cornerRadius: CGFloat, size: CGSize, tintSource: String? = nil) -> some View {
        modifier(DetailTileFocusLift(cornerRadius: cornerRadius, size: size, tintSource: tintSource))
    }
}

/// BUG-177: the rail-colour half of "Depth Takes Poster Color" for the three Detail tiles, as
/// `FolderTile` does it: a store peek first (a colour sampled elsewhere is on the rail from the
/// first frame), then the tile's own `@State`, written once when its image lands.
@MainActor
enum DetailTileRailTint {
    /// The tint handed to `nuvioCardDepth`. `sampled` is the tile's own `@State`.
    static func resolved(samples: Bool, source: String?, sampled: Color?) -> Color? {
        guard samples else { return nil }
        return ArtworkColorStore.shared.cachedColor(for: [source], use: .rail) ?? sampled
    }

    /// Call from `CachedAsyncImage.onImageLoaded`. No animation: the image's own fade is running.
    /// A store hit is already on the rail via `resolved`, so it writes no state.
    static func imageLoaded(samples: Bool, source: String?, store: @escaping @MainActor (Color?) -> Void) {
        guard samples else { return }
        if ArtworkColorStore.shared.cachedColor(for: [source], use: .rail) != nil { return }
        ArtworkColorStore.shared.color(for: [source], use: .rail, completion: store)
    }
}
