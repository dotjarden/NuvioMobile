import SwiftUI

/// A remote-first selection panel. Opaque content prevents artwork behind it reducing contrast.
struct TVSelectionMenu: View {
    let title: String
    let value: String
    let options: [String]
    let select: (String) -> Void
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            HStack(spacing: 12) { Text(value).lineLimit(1); Image(systemName: "chevron.down").font(.caption) }
        }.buttonStyle(.glass).accessibilityLabel("\(title): \(value)")
        .fullScreenCover(isPresented: $presented) {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 28) {
                    Text(title).font(.title2.bold())
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(options, id: \.self) { option in
                                Button { select(option); presented = false } label: {
                                    HStack { Text(option); Spacer(); if option == value { Image(systemName: "checkmark") } }
                                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.card)
                            }
                        }.padding(16)
                    }
                    Button("Cancel") { presented = false }.buttonStyle(.glass)
                }.frame(width: 850).padding(60)
            }.preferredColorScheme(.dark)
            .presentationBackground(Theme.Palette.background)
        }
    }
}
