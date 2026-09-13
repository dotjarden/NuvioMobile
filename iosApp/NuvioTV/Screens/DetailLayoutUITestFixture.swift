#if DEBUG
import SharedCore
import SwiftUI

/// Isolated content for focus/layout checks; never starts account or metadata repositories.
struct DetailLayoutUITestFixture: View {
    private let preview = MetaPreview(id: "detail-layout", type: "series", name: "North Coast",
        poster: nil, banner: nil, logo: nil, posterShape: .poster,
        description: nil, releaseInfo: "2026", rawReleaseDate: nil, popularity: nil,
        voteCount: nil, imdbRating: "8.4", genres: ["Drama", "Mystery"])

    var body: some View {
        NavigationStack {
            DetailView(preview: preview, fixture: Self.metadata)
        }
    }

    static var metadata: MetaDetails {
        let synopsis = Array(repeating: "A coastal community is brought together when an unexpected discovery challenges everything its residents thought they knew. As the investigation unfolds, old friendships and new alliances reveal the town's hidden history.", count: 3).joined(separator: " ")
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
#endif
