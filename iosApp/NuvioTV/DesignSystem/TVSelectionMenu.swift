import SwiftUI

/// Native anchored menu: Select opens it beside the control; Back closes it without leaving the page.
struct TVSelectionMenu: View {
    let title: String
    let value: String
    let options: [String]
    let select: (String) -> Void
    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { value }, set: select)) {
                ForEach(options, id: \.self) { option in Text(option).tag(option) }
            }
        } label: {
            HStack(spacing: 12) {
                Text(value).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption)
            }
        }.buttonStyle(.glass).accessibilityLabel("\(title): \(value)")
    }
}
