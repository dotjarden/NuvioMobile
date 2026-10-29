import SwiftUI

/// FEAT-35 (D3): the full synopsis, opened from the Cinematic hero's teaser when the text does not
/// fit its four lines. Presented as a full-screen cover; Menu closes it through the system's own
/// cover dismissal (no `onExitCommand`: Menu = back, per the remote-grammar rule).
///
/// BUG-193 (Steven rc10): the backdrop is the page's own backdrop under a flat dark scrim, a plain
/// fade with no blur (the `.thick` material it replaces read as a blurred smear on his OLED). It is
/// a background LAYER over the cover's default opaque background — never a `.presentationBackground`.
/// A clear cover background keeps the presenting page alive under it, and one Menu press then
/// dismissed the cover AND popped Detail (FEAT-32, 2026-09-05; correction F8). The layers also
/// never wrap anything focusable.
struct DetailSynopsisSheet: View {
    let title: String
    let logoURL: String?
    let overview: String
    /// BUG-193: the same backdrop URL the Detail page draws (already upgraded). The page releases
    /// its own bitmap while covered, so this is normally a memory-cache hit. Nil (the biography)
    /// draws the app background under the same scrim.
    var backdropURL: String? = nil
    /// The page's fallback chain entry (the original URL when `backdropURL` is an upgraded one).
    var backdropFallbackURL: String? = nil

    @State private var position = ScrollPosition()
    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var textVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flat scrim over the backdrop. The text needs at least the Cinematic text-block floor
    /// (`DetailScrimCinematicTests.testTextBlockFloor`, 0.31); 0.72 is comfortably dark. Tune on the rig.
    static let scrimOpacity: Double = 0.72

    /// One D-pad press scrolls this far.
    private static let pageStep: CGFloat = 240

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdropLayers
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // The fade sits on the logo and the text only: the focusable scroll view itself is
                // never at opacity 0 (an opacity-0 control is unfocusable on hardware).
                logo
                    .opacity(textVisible || reduceMotion ? 1 : 0)
                ScrollView(.vertical) {
                    Text(overview)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 1400, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(textVisible || reduceMotion ? 1 : 0)
                        .accessibilityIdentifier("detail_synopsis_sheet_text")
                }
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, newOffset in
                    offset = newOffset
                })
                .onScrollGeometryChange(for: CGFloat.self, of: { geo in
                    max(0, geo.contentSize.height - geo.containerSize.height)
                }, action: { _, newMax in
                    maxOffset = newMax
                })
                // tvOS cannot focus or scroll a ScrollView with no focusable content, so the scroll
                // view itself is the (inert) focus target and the D-pad pages it.
                .focusable()
                .onMoveCommand { direction in
                    switch direction {
                    case .down: scroll(to: min(offset + Self.pageStep, maxOffset))
                    case .up: scroll(to: max(offset - Self.pageStep, 0))
                    default: break
                    }
                }
            }
            .padding(Theme.Spacing.screen)
        }
        .onAppear {
            guard !textVisible else { return }
            if reduceMotion { textVisible = true } else {
                withAnimation(.easeOut(duration: 0.25)) { textVisible = true }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_synopsis_sheet")
    }

    /// App background, then (when there is one) the page's backdrop full-bleed, then the flat scrim.
    /// No blur, no material.
    private var backdropLayers: some View {
        ZStack {
            Theme.Palette.background
            if let backdropURL, !backdropURL.isEmpty {
                GeometryReader { geo in
                    CachedAsyncImage(string: backdropURL, fallback: backdropFallbackURL, decodeSize: .fullBleed)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                #if DEBUG
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "synopsis backdrop"))
                .accessibilityIdentifier("detail_synopsis_backdrop")
                #endif
            }
            Color.black.opacity(Self.scrimOpacity)
        }
        .ignoresSafeArea()
        #if !DEBUG
        .accessibilityHidden(true)
        #endif
    }

    @ViewBuilder
    private var logo: some View {
        let fallback = Text(title)
            .font(Theme.Font.screenTitle)
            .foregroundStyle(Theme.Palette.textPrimary)
        if let logoURL, !logoURL.isEmpty {
            // beta.19-rc1 verdict (I1, BUG-134): the TMDB `original` logo (the data keeps w500; the
            // w500 file is the automatic fallback), decoded for the 520×120 box it is drawn in. The
            // spec lists 600×180 here; the box below is the real drawn size.
            CachedAsyncImage(string: logoURL, contentMode: .fit,
                             decodeSize: .points(width: 520, height: 120), upgrade: .logo,
                             failure: { fallback })
                .frame(maxWidth: 520, maxHeight: 120, alignment: .leading)
        } else {
            fallback
        }
    }

    private func scroll(to y: CGFloat) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { position.scrollTo(y: y) }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(y: y) }
        }
    }
}
