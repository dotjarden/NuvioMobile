import SwiftUI

/// One complete synopsis in the page scroll, with no disclosure action or second copy.
struct DetailSynopsisView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(DetailReadingBlock.paragraphs(text).enumerated()), id: \.offset) { index, paragraph in
                DetailReadingBlock(id: "detail.synopsis.\(index)") {
                    Text(paragraph).font(Theme.Font.body)
                }
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .foregroundStyle(Theme.Palette.textPrimary)
    }
}
