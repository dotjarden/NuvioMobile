import SwiftUI

/// FEAT-82 (Steven rc10, D4): with Poster › Corners = Square, every icon-only Detail action button
/// (Start Over, Watch Trailer, Mark Watched, Add to Library, Shuffle) is one equal square whose side
/// is Play's measured height. An icon-only label is its SF Symbol's own aspect plus 32 pt of padding,
/// so the buttons differ from each other (`play.rectangle.fill` is wider than `plus`) and no shape
/// change can equalise them; a fixed frame can.
///
/// The trick that needs no knowledge of the glass chrome's padding: a button style sizes its chrome
/// to the label plus padding, so a label that is flexible (`maxWidth/maxHeight: .infinity`) inside a
/// button given a fixed outer `side × side` frame makes the chrome exactly that size. If the `.glass`
/// style on tvOS 26 ignores the proposal, the fallback is to measure the chrome once.
///
/// Rounded and Round, and Classic with text labels, never see a side (nil) and keep today's layout.
nonisolated enum DetailActionSquare {
    /// The square's side: Play's measured padded-label height (whole points), or nil until Play
    /// has been measured (0 or a sliver).
    static func side(playHeight: CGFloat) -> CGFloat? {
        playHeight > 1 ? playHeight.rounded() : nil
    }

    /// Whether a button takes the fixed square: Corners = Square, an icon-only label, a measured side.
    static func applies(isSquare: Bool, iconOnly: Bool, side: CGFloat?) -> Bool {
        isSquare && iconOnly && side != nil
    }
}

/// The padded icon label sized to a `side × side` square (side = Play's padded label height), so
/// the button style adds the same insets to every button and the secondaries match Play's height.
struct DetailActionSquareLabel: ViewModifier {
    let side: CGFloat?

    func body(content: Content) -> some View {
        if let side {
            content.frame(width: side, height: side)
        } else {
            content
        }
    }
}
