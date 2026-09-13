import SwiftUI

/// A read-only focus stop lets the Siri Remote scroll information without button/pill chrome.
struct DetailReadingBlock<Content: View>: View {
    let id: String
    @ViewBuilder var content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(focused ? Theme.Palette.textPrimary : .clear).frame(width: 2)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }
}

extension DetailReadingBlock where Content == Text {
    /// Bounded focus stops for long descriptions, so Up/Down can reach both ends on TV.
    static func paragraphs(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        var result: [String] = [], current = ""
        for sentence in sentences {
            if !current.isEmpty, current.count + sentence.count > 340 {
                result.append(current); current = ""
            }
            // Keep ordinary sentences together; bound unusually long ones for remote scrolling.
            for word in sentence.split(whereSeparator: \.isWhitespace) {
                if !current.isEmpty, current.count + word.count > 460 {
                    result.append(current); current = ""
                }
                current += (current.isEmpty ? "" : " ") + word
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
