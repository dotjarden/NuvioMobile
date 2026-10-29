import Foundation

/// UX-19 (2026-10-22): the hero's text wordmark (`HeroLogo`'s stand-in when there is no logo) must
/// never be a content id. A Continue Watching entry built from a progress row before its metadata
/// resolved carries the id as its name (`TraktProgressRepository`: `title = movie.title ?:
/// parentMetaId`; `MdbListProgressProjection`: `media.title ?: media.ids.contentId`; shared
/// `needsRemoteMetadataEnrichment` tests the same `title == parentMetaId`), and on one launch the
/// Stage printed "tt3118958" where the title belongs.
nonisolated enum HeroTitleText {
    /// The name IS the item's own id (or its head before a `:1:7` suffix), or has an id's shape:
    /// IMDb (`tt1234567`), a prefixed id (`tmdb:…`, `trakt:…`, `kitsu:…`, `mal:…`, `anilist:…`,
    /// `anidb:…`, `simkl:…`, `tvdb:…`, `imdb:tt…`), either with an optional season/episode suffix.
    /// Never a bare number (review r1 P2-5: "1917", "300", "2012" are titles), and ASCII digits only.
    static func isIdentifier(_ name: String, id: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let id, !id.isEmpty {
            let lower = trimmed.lowercased(), idLower = id.lowercased()
            // The fallbacks set the name to the id or to the id's head, nothing looser: "Lost: Season 1"
            // against a slug id "lost" is a title (review r2 P3).
            if lower == idLower || lower == head(of: idLower) { return true }
        }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { String($0).lowercased() }
        guard let first = parts.first else { return false }
        func digits(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }
        func episodeTail(_ rest: ArraySlice<String>) -> Bool { rest.allSatisfy { digits(Substring($0)) } }
        if first.hasPrefix("tt"), digits(first.dropFirst(2)) { return episodeTail(parts.dropFirst()) }
        let prefixes = ["tmdb", "trakt", "kitsu", "mal", "anilist", "anidb", "simkl", "tvdb", "imdb"]
        if parts.count >= 2, prefixes.contains(first) {
            let body = Substring(parts[1])
            let bodyIsId = digits(body) || (first == "imdb" && body.hasPrefix("tt") && digits(body.dropFirst(2)))
            return bodyIsId && episodeTail(parts.dropFirst(2))
        }
        return false
    }

    /// The id without a `:season:episode` suffix: `tt1:1:7` → `tt1`, `tmdb:12:1:7` → `tmdb:12`,
    /// `abc-custom-9` → itself.
    private static func head(of id: String) -> String {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return id }
        func digits(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }
        // A prefixed id keeps its first two parts when the second is the number body.
        if !parts[0].hasPrefix("tt"), !digits(parts[0]), digits(parts[1]) { return parts[0] + ":" + parts[1] }
        return parts[0]
    }
}
