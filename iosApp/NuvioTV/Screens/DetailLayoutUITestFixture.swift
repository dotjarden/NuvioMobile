#if DEBUG
import SharedCore
import SwiftUI

/// Isolated content for focus/layout checks; never starts account or metadata repositories.
struct DetailLayoutUITestFixture: View {
    static let preview = MetaPreview(id: "detail-layout", type: "series", name: "North Coast",
        poster: nil, banner: nil, logo: nil, posterShape: .poster,
        description: nil, releaseInfo: "2026", rawReleaseDate: nil, popularity: nil,
        voteCount: nil, imdbRating: "8.4", genres: ["Drama", "Mystery"])

    var body: some View {
        NavigationStack {
            DetailView(preview: Self.preview, fixture: Self.metadata)
        }
    }

    static var metadata: MetaDetails {
        let synopsis = "A coastal community is brought together when an unexpected discovery challenges everything its residents thought they knew. As the investigation unfolds, old friendships and new alliances reveal the town's hidden history. A young journalist follows a trail of letters to a lighthouse that has stood empty for decades. Her search takes her beyond the harbor and into the lives of families who have kept their secrets for generations. With a storm approaching and the ferry service suspended, the residents must decide whom to trust before the truth disappears with the tide."

        let data: [String: Any] = ["meta": [
            "id": "detail-layout", "type": "series", "name": "North Coast", "description": synopsis,
            "releaseInfo": "2026", "runtime": "48 min", "imdbRating": "8.4", "ageRating": "TV-14",
            "director": ["Alex Morgan"], "writer": ["Sam Rivera", "Taylor Brooks"],
            "country": "United States", "language": "English", "awards": "Audience Choice Award", "status": "Returning Series",
            "genres": ["Drama", "Mystery"],
            "videos": [
                ["id": "s1e1", "title": "The Arrival", "season": 1, "episode": 1, "overview": "A stranger arrives on the coast."],
                ["id": "s1e2", "title": "Low Tide", "season": 1, "episode": 2],
                ["id": "s2e1", "title": "The Return", "season": 2, "episode": 1],
                ["id": "special", "title": "Behind the Scenes", "season": 0, "episode": 1]
            ]
        ]]
        return MetaDetailsParser.shared.parse(payload: String(data: try! JSONSerialization.data(withJSONObject: data), encoding: .utf8)!)
    }
}
/// Real native tabs, pinned controls and immersive DetailView without external catalog data.
struct NavigationLayoutUITestFixture: View {
    @State private var selectedTab = 0
    @State private var visibility = TabBarVisibility()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: 0) { root("Home") }
            Tab("Search", systemImage: "magnifyingglass", value: 1) { root("Search") }
            Tab("Settings", systemImage: "gearshape", value: 2) { root("Settings") }
        }
        .background { TabBarPresentation(visibility: visibility).frame(width: 0, height: 0) }
        .environment(\.tabBarVisibility, visibility)
    }

    private func root(_ name: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Menu("Genre") { Button("All genres") {} ; Button("Drama") {} }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("nav.filter.\(name)")
                ScrollView {
                    VStack(alignment: .leading, spacing: 35) {
                        NavigationLink {
                            DetailView(preview: DetailLayoutUITestFixture.preview, fixture: DetailLayoutUITestFixture.metadata)
                        } label: { Text("North Coast") }
                        .accessibilityIdentifier("nav.detail.\(name)")
                        ForEach(0..<12) { index in
                            Button("\(name) title \(index)") {}
                                .accessibilityIdentifier("nav.row.\(name).\(index)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 30)
                }
            }
            .padding(60)
        }
    }
}
#endif
