import Foundation

/// UX-19 (2026-10-22): the hero's text wordmark (`HeroLogo`'s stand-in when there is no logo) must
/// never be a content id. A Continue Watching entry built from a progress row before its metadata
/// resolved carries the id as its name (`TraktProgressRepository`: `title = movie.title ?:
/// parentMetaId`; `MdbListProgressProjection`: `media.title ?: media.ids.contentId`), and on one
/// launch the Stage printed "tt3118958" where the title belongs.
nonisolated enum HeroTitleText {
    /// IMDb (`tt1234567`), a prefixed id (`tmdb:…`, `trakt:…`, `kitsu:…`, `mal:…`, `anilist:…`,
    /// `simkl:…`), a bare number, or an id with a season/episode suffix (`tt1234567:1:7`).
    static func isIdentifier(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let base = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(base[0]).lowercased()
        if head.hasPrefix("tt"), head.count > 2, head.dropFirst(2).allSatisfy(\.isNumber) { return true }
        if head.allSatisfy(\.isNumber) { return true }
        let prefixes = ["tmdb", "trakt", "kitsu", "mal", "anilist", "simkl", "imdb", "tvdb"]
        if base.count == 2, prefixes.contains(head) {
            let tail = base[1]
            return !tail.isEmpty && tail.allSatisfy { $0.isNumber || $0 == ":" }
        }
        return false
    }
}
