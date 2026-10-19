import Foundation

// BUG-189 (Steven rc9, French): Discover's genre and catalog names come straight from the add-on
// manifests, so they stayed English under every app language. This maps the standard names
// Cinemeta and TMDB-based add-ons publish to app strings, for DISPLAY only: selection,
// persistence, fetch keys (`DiscoverRowSpec.genre`, the pill values) and the catalog-clash check
// all keep the raw manifest name. Matching is trimmed and case-insensitive; a name not in the
// table passes through unchanged (custom add-ons, already-localized manifests).
//
// Pinned by `DiscoverGenreNamesTests`.
nonisolated enum DiscoverGenreNames {
    /// The localized label for a manifest genre name, or `raw` itself when it isn't a standard one.
    static func display(_ raw: String) -> String {
        switch normalized(raw) {
        // Cinemeta
        case "action": return String(localized: "Action", comment: "Discover genre")
        case "adventure": return String(localized: "Adventure", comment: "Discover genre")
        case "animation": return String(localized: "Animation", comment: "Discover genre")
        case "biography": return String(localized: "Biography", comment: "Discover genre")
        case "comedy": return String(localized: "Comedy", comment: "Discover genre")
        case "crime": return String(localized: "Crime", comment: "Discover genre")
        case "documentary": return String(localized: "Documentary", comment: "Discover genre")
        case "drama": return String(localized: "Drama", comment: "Discover genre")
        case "family": return String(localized: "Family", comment: "Discover genre")
        case "fantasy": return String(localized: "Fantasy", comment: "Discover genre")
        case "history": return String(localized: "History", comment: "Discover genre")
        case "horror": return String(localized: "Horror", comment: "Discover genre")
        case "mystery": return String(localized: "Mystery", comment: "Discover genre")
        case "romance": return String(localized: "Romance", comment: "Discover genre")
        case "sci-fi": return String(localized: "Sci-Fi", comment: "Discover genre")
        case "sport": return String(localized: "Sport", comment: "Discover genre")
        case "thriller": return String(localized: "Thriller", comment: "Discover genre")
        case "war": return String(localized: "War", comment: "Discover genre")
        case "western": return String(localized: "Western", comment: "Discover genre")
        case "reality-tv": return String(localized: "Reality-TV", comment: "Discover genre")
        case "talk-show": return String(localized: "Talk-Show", comment: "Discover genre")
        case "game-show": return String(localized: "Game-Show", comment: "Discover genre")
        case "news": return String(localized: "News", comment: "Discover genre")
        case "film-noir": return String(localized: "Film-Noir", comment: "Discover genre")
        case "music": return String(localized: "Music", comment: "Discover genre")
        case "musical": return String(localized: "Musical", comment: "Discover genre")
        case "short": return String(localized: "Short", comment: "Discover genre")
        // TMDB
        case "science fiction": return String(localized: "Science Fiction", comment: "Discover genre")
        case "tv movie": return String(localized: "TV Movie", comment: "Discover genre")
        case "action & adventure": return String(localized: "Action & Adventure", comment: "Discover genre")
        case "sci-fi & fantasy": return String(localized: "Sci-Fi & Fantasy", comment: "Discover genre")
        case "war & politics": return String(localized: "War & Politics", comment: "Discover genre")
        case "kids": return String(localized: "Kids", comment: "Discover genre")
        case "soap": return String(localized: "Soap", comment: "Discover genre")
        default: return raw
        }
    }

    /// The localized label for a standard catalog name ("Popular", "Top Rated", …), or `raw`.
    static func catalogDisplay(_ raw: String) -> String {
        switch normalized(raw) {
        case "popular": return String(localized: "Popular", comment: "Discover catalog")
        case "featured": return String(localized: "Featured", comment: "Discover catalog")
        case "trending": return String(localized: "Trending", comment: "Discover catalog")
        case "new": return String(localized: "New", comment: "Discover catalog")
        case "top rated": return String(localized: "Top Rated", comment: "Discover catalog")
        default: return raw
        }
    }

    /// Review r1 (BUG-189): the display labels for a genre LIST, in order. Two raw names can map
    /// to the same label ("Sci-Fi" and "Science Fiction" under one translation, "Action" and
    /// "action" under any), which would show two identical entries. The first raw name takes the
    /// localized label; a later one whose label repeats an earlier label shows its RAW name. The
    /// values themselves (pill values, fetch genres, row keys) never change.
    static func displayLabels(_ raws: [String], display: (String) -> String = DiscoverGenreNames.display) -> [String] {
        var seen = Set<String>()
        return raws.map { raw in
            let label = display(raw)
            let shown = seen.contains(normalized(label)) ? raw : label
            seen.insert(normalized(shown))
            return shown
        }
    }

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
