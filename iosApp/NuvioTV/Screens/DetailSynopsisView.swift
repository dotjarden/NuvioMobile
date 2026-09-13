import SwiftUI

/// The title's only synopsis. Expands in place, with bounded remote-readable text blocks.
struct DetailSynopsisView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if expanded {
                ForEach(Array(DetailReadingBlock.paragraphs(text).enumerated()), id: \.offset) { index, paragraph in
                    DetailReadingBlock(id: "detail.synopsis.\(index)") {
                        Text(paragraph).font(Theme.Font.body)
                    }
                }
            } else {
                Text(text).font(Theme.Font.body).lineLimit(3)
                    .accessibilityIdentifier("detail.synopsis.preview")
            }
            if text.count > 200 {
                Button(expanded ? String(localized: "Show Less") : String(localized: "Read More")) {
                    expanded.toggle()
                }
                .font(Theme.Font.caption)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("detail.synopsis.toggle")
                .accessibilityValue(expanded ? "expanded" : "collapsed")
            }
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .foregroundStyle(Theme.Palette.textPrimary)
    }
}
