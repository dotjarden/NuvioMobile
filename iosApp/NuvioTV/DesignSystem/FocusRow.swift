import SwiftUI

extension View {
    /// One row of a vertically stacked form or page, as a single focus target for Up/Down.
    ///
    /// The tvOS focus engine only moves to a focusable whose frame overlaps the source's
    /// projection in the pressed direction. A column of centred rows with different widths
    /// (a TextField, a strip of swatches, one or two chips, a lone button) therefore strands
    /// focus: Down from the rightmost swatch finds nothing under it when the next row is
    /// narrower. Stretching each row to full width and making it a focus section lets any
    /// vertical press land in the next row, on the child nearest the source (or the one it
    /// last left). Left/Right inside the row are unchanged.
    ///
    /// Use on every row of a vertical form whose rows are not all the same width. Rows that
    /// are already full-width lists or grids don't need it.
    func focusRow(alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .focusSection()
    }
}
