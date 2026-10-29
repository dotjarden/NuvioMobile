import XCTest
@testable import NuvioTV
import SharedCore

/// BUG-151 (Steven rc3/rc4): the pure decisions behind `StageLocalizedCopyStore`
/// (`DesignSystem/StageLocalizedCopyStore.swift`). Like `TitleLogoStoreTests`, the singleton itself
/// is not driven here (it reaches `TmdbSettingsRepository.shared` / `TmdbMetadataService.shared`);
/// every decision it makes is a `nonisolated static` function pinned below.
final class StageLocalizedCopyStoreTests: XCTestCase {

    private typealias Store = StageLocalizedCopyStore

    private func makeItem(id: String = "tt0111161",
                          type: String = "movie",
                          name: String = "The Shawshank Redemption",
                          description: String? = "Two imprisoned men bond.",
                          genres: [String] = ["Drama"],
                          logo: String? = "https://example.com/logo.png") -> MetaPreview {
        MetaPreview(
            id: id, type: type, name: name,
            poster: "https://example.com/poster.jpg", banner: "https://example.com/banner.jpg", logo: logo,
            posterShape: .poster,
            description: description, releaseInfo: "1994", rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: "9.3",
            genres: genres,
            rawPosterUrl: "https://example.com/raw.jpg",
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: true
        )
    }

    private let french = StageLocalizedCopy(title: "Les Évadés",
                                            overview: "Deux prisonniers se lient d'amitié.",
                                            genres: ["Drame"])

    // MARK: - Key and scope

    func testKeyCarriesEveryScopeSetting() {
        let base = Store.key(type: "movie", id: "tt1", language: "fr", enabled: true, useBasicInfo: true)
        XCTAssertEqual(base, "movie|tt1|fr|true|true")
        XCTAssertNotEqual(base, Store.key(type: "movie", id: "tt1", language: "en", enabled: true, useBasicInfo: true))
        XCTAssertNotEqual(base, Store.key(type: "series", id: "tt1", language: "fr", enabled: true, useBasicInfo: true))
        XCTAssertNotEqual(base, Store.key(type: "movie", id: "tt1", language: "fr", enabled: false, useBasicInfo: true))
        XCTAssertNotEqual(base, Store.key(type: "movie", id: "tt1", language: "fr", enabled: true, useBasicInfo: false))
    }

    func testEligibleForAnOrdinaryTitle() {
        XCTAssertTrue(Store.isEligible(type: "movie", id: "tt1", enabled: true, useBasicInfo: true))
        // No resolvable TMDB id is still eligible: the lookup resolves to nil.
        XCTAssertTrue(Store.isEligible(type: "series", id: "kitsu:123", enabled: true, useBasicInfo: true))
    }

    func testNotEligibleWhenTmdbOrBasicInfoIsOff() {
        XCTAssertFalse(Store.isEligible(type: "movie", id: "tt1", enabled: false, useBasicInfo: true))
        XCTAssertFalse(Store.isEligible(type: "movie", id: "tt1", enabled: true, useBasicInfo: false))
    }

    func testNotEligibleForFoldersOrBlankIds() {
        XCTAssertFalse(Store.isEligible(type: StageCopy.folderType, id: "\(StageCopy.folderIdScheme)c/f",
                                        enabled: true, useBasicInfo: true))
        XCTAssertFalse(Store.isEligible(type: "movie", id: "  ", enabled: true, useBasicInfo: true))
    }

    // MARK: - Blank handling

    func testCopyDropsBlankFields() {
        XCTAssertNil(Store.copy(title: "  ", overview: "", genres: [" ", ""]))
        XCTAssertNil(Store.copy(title: nil, overview: nil, genres: []))
        let partial = Store.copy(title: " Les Évadés ", overview: "  ", genres: ["Drame", " "])
        XCTAssertEqual(partial, StageLocalizedCopy(title: "Les Évadés", overview: nil, genres: ["Drame"]))
    }

    func testCompletionOutcome() {
        let error = NSError(domain: "test", code: 1)
        XCTAssertEqual(Store.completionOutcome(enrichment: nil, error: error), .failed)
        XCTAssertEqual(Store.completionOutcome(enrichment: nil, error: nil), .resolved(nil))
        let enrichment = TmdbPreviewEnrichment(localizedTitle: "Les Évadés", description: " ",
                                               genres: [], logo: nil, backdrop: nil)
        XCTAssertEqual(Store.completionOutcome(enrichment: enrichment, error: nil),
                       .resolved(StageLocalizedCopy(title: "Les Évadés", overview: nil, genres: nil)))
    }

    func testCommitNeverReplacesWithBlank() {
        let item = makeItem()
        let titleOnly = StageLocalizedCopy(title: "Les Évadés", overview: nil, genres: nil)
        let applied = Store.applying(titleOnly, to: item, mode: .commit)
        XCTAssertEqual(applied.name, "Les Évadés")
        XCTAssertEqual(applied.description_, "Two imprisoned men bond.")
        XCTAssertEqual(applied.genres, ["Drama"])
    }

    // MARK: - Applying

    func testCommitAppliesEveryLocalizedFieldAndKeepsTheRest() {
        let item = makeItem()
        let applied = Store.applying(french, to: item, mode: .commit)
        XCTAssertEqual(applied.name, "Les Évadés")
        XCTAssertEqual(applied.description_, "Deux prisonniers se lient d'amitié.")
        XCTAssertEqual(applied.genres, ["Drame"])
        XCTAssertEqual(applied.id, item.id)
        XCTAssertEqual(applied.type, item.type)
        XCTAssertEqual(applied.logo, item.logo)
        XCTAssertEqual(applied.banner, item.banner)
        XCTAssertEqual(applied.releaseInfo, item.releaseInfo)
        XCTAssertEqual(applied.imdbRating, item.imdbRating)
        XCTAssertEqual(applied.rawPosterUrl, item.rawPosterUrl)
        XCTAssertEqual(applied.customPosterApplied, item.customPosterApplied)
    }

    func testGapFillNeverTouchesTheNameOrExistingText() {
        let item = makeItem()
        XCTAssertTrue(Store.applying(french, to: item, mode: .gapFill) === item)
    }

    func testGapFillFillsMissingSynopsisAndGenres() {
        let item = makeItem(description: "", genres: [])
        let applied = Store.applying(french, to: item, mode: .gapFill)
        XCTAssertEqual(applied.name, "The Shawshank Redemption")
        XCTAssertEqual(applied.description_, "Deux prisonniers se lient d'amitié.")
        XCTAssertEqual(applied.genres, ["Drame"])
    }

    func testNoChangeReturnsTheSameInstance() {
        let item = makeItem()
        XCTAssertTrue(Store.applying(nil, to: item, mode: .commit) === item)
        let localized = Store.applying(french, to: item, mode: .commit)
        XCTAssertTrue(Store.applying(french, to: localized, mode: .commit) === localized)
    }

    func testAdoptModeKeepsTheLanguageOnScreen() {
        let raw = makeItem()
        let localized = Store.applying(french, to: raw, mode: .commit)
        XCTAssertEqual(Store.adoptMode(shown: localized, copy: french), .commit)
        XCTAssertEqual(Store.adoptMode(shown: raw, copy: french), .gapFill)
        XCTAssertEqual(Store.adoptMode(shown: nil, copy: french), .gapFill)
        XCTAssertEqual(Store.adoptMode(shown: localized, copy: nil), .gapFill)
    }

    func testAdoptModeIgnoresAGapFilledSynopsisUnderTheCatalogName() {
        // Committed in English, then `enrichIfNeeded` filled the missing synopsis in French.
        let shown = Store.applying(french, to: makeItem(description: nil), mode: .gapFill)
        XCTAssertEqual(shown.name, "The Shawshank Redemption")
        XCTAssertEqual(Store.adoptMode(shown: shown, copy: french), .gapFill)
        // A copy with no localized title falls back to the synopsis.
        let overviewOnly = StageLocalizedCopy(title: nil, overview: french.overview, genres: nil)
        XCTAssertEqual(Store.adoptMode(shown: shown, copy: overviewOnly), .commit)
    }

    // MARK: - Commit guard, cooldown, cap

    func testShouldCommitOnlyForTheLiveRequest() {
        XCTAssertTrue(Store.shouldCommit(entry: .pending(requestId: 4), requestId: 4))
        XCTAssertFalse(Store.shouldCommit(entry: .pending(requestId: 5), requestId: 4))
        XCTAssertFalse(Store.shouldCommit(entry: .resolved(nil), requestId: 4))
        XCTAssertFalse(Store.shouldCommit(entry: nil, requestId: 4))
    }

    func testRetryCooldown() {
        let now = Date()
        XCTAssertFalse(Store.shouldSkipRetry(lastFailure: nil, now: now, cooldown: 30))
        XCTAssertTrue(Store.shouldSkipRetry(lastFailure: now.addingTimeInterval(-10), now: now, cooldown: 30))
        XCTAssertFalse(Store.shouldSkipRetry(lastFailure: now.addingTimeInterval(-31), now: now, cooldown: 30))
    }

    func testEvictionBelowCapKeepsEverything() {
        let entries: [String: Store.Entry] = ["a": .resolved(nil), "b": .pending(requestId: 1)]
        XCTAssertEqual(Store.evictingResolved(entries, cap: 3), entries)
    }

    func testEvictionAtCapDropsOnlyResolved() {
        let entries: [String: Store.Entry] = [
            "a": .resolved(nil),
            "b": .pending(requestId: 1),
            "c": .resolved(french),
        ]
        XCTAssertEqual(Store.evictingResolved(entries, cap: 3), ["b": .pending(requestId: 1)])
    }

    // MARK: - Queue

    private func keys(_ queue: [Store.QueuedKey]) -> [String] { queue.map(\.key) }

    func testPrefetchAppendsAndCommitJumpsAhead() {
        var queue: [Store.QueuedKey] = []
        queue = Store.enqueued(queue, key: "a", priority: false, limit: 10).queue
        queue = Store.enqueued(queue, key: "b", priority: false, limit: 10).queue
        queue = Store.enqueued(queue, key: "c", priority: true, limit: 10).queue
        XCTAssertEqual(keys(queue), ["c", "a", "b"])
    }

    func testCommitPromotesAWaitingPrefetch() {
        var queue: [Store.QueuedKey] = []
        queue = Store.enqueued(queue, key: "a", priority: false, limit: 10).queue
        queue = Store.enqueued(queue, key: "b", priority: false, limit: 10).queue
        let result = Store.enqueued(queue, key: "b", priority: true, limit: 10)
        XCTAssertEqual(keys(result.queue), ["b", "a"])
        XCTAssertEqual(result.queue.first?.priority, true)
        XCTAssertEqual(result.dropped, [])
    }

    func testRepeatedPrefetchIsANoOp() {
        let queue = Store.enqueued([], key: "a", priority: false, limit: 10).queue
        let again = Store.enqueued(queue, key: "a", priority: false, limit: 10)
        XCTAssertEqual(again.queue, queue)
        XCTAssertEqual(again.dropped, [])
    }

    func testOverflowDropsTheOldestPrefetchNeverACommit() {
        var queue: [Store.QueuedKey] = []
        queue = Store.enqueued(queue, key: "p1", priority: false, limit: 3).queue
        queue = Store.enqueued(queue, key: "p2", priority: false, limit: 3).queue
        queue = Store.enqueued(queue, key: "c1", priority: true, limit: 3).queue
        let result = Store.enqueued(queue, key: "p3", priority: false, limit: 3)
        XCTAssertEqual(keys(result.queue), ["c1", "p2", "p3"])
        XCTAssertEqual(result.dropped, ["p1"])
    }
}
