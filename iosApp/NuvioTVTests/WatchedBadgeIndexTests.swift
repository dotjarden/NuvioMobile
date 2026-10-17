import XCTest
@testable import NuvioTV
import SharedCore

/// FEAT-64: the watched tick's index (`DesignSystem/WatchedBadgeIndex.swift`) over the shared
/// repository's key strings (`watchedKey`: `"<type>:<id>:<season or -1>:<episode or -1>"`).
@MainActor
final class WatchedBadgeIndexTests: XCTestCase {

    private func preview(id: String, type: String) -> MetaPreview {
        MetaPreview(
            id: id, type: type, name: "Title",
            poster: nil, banner: nil, logo: nil,
            posterShape: .poster,
            description: nil, releaseInfo: nil, rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: nil,
            genres: [],
            rawPosterUrl: nil,
            landscapePoster: nil,
            rawLandscapePosterUrl: nil,
            customPosterApplied: false
        )
    }

    /// The test keys are the shared helper's own output, so a format change upstream breaks here.
    private func key(_ type: String, _ id: String, season: Int32? = nil, episode: Int32? = nil) -> String {
        WatchedModelsKt.watchedItemKey(type: type, id: id,
                                       season: season.map { KotlinInt(int: $0) },
                                       episode: episode.map { KotlinInt(int: $0) })
    }

    func testMovieMarkTicksTheMovie() {
        let index = WatchedBadgeIndex()
        index.receive(watchedKeys: [key("movie", "tt1")], fullyWatchedSeriesKeys: [])
        XCTAssertTrue(index.isWatched(preview(id: "tt1", type: "movie")))
        XCTAssertEqual(index.badge(for: preview(id: "tt1", type: "movie")),
                       PosterWatchBadge(isWatched: true, progress: nil))
        XCTAssertFalse(index.isWatched(preview(id: "tt2", type: "movie")))
        XCTAssertNil(index.badge(for: preview(id: "tt2", type: "movie")))
        // The shared aliases: a "film" mark is the same title as a "movie" card.
        index.receive(watchedKeys: [key("film", "tt3")], fullyWatchedSeriesKeys: nil)
        XCTAssertTrue(index.isWatched(preview(id: " tt3 ", type: "Movie")))
    }

    func testSeriesTicksOnlyWhenFullyWatched() {
        let index = WatchedBadgeIndex()
        // Two episodes watched, not the whole show: no tick.
        index.receive(watchedKeys: [key("series", "tt9", season: 1, episode: 1),
                                    key("series", "tt9", season: 1, episode: 2)],
                      fullyWatchedSeriesKeys: [])
        XCTAssertFalse(index.isWatched(preview(id: "tt9", type: "series")))
        // Fully watched: tick, under any series alias.
        index.receive(watchedKeys: nil, fullyWatchedSeriesKeys: [key("series", "tt9")])
        XCTAssertTrue(index.isWatched(preview(id: "tt9", type: "series")))
        XCTAssertTrue(index.isWatched(preview(id: "tt9", type: "tv")))
        // The fully-watched set never ticks a movie with the same id.
        XCTAssertFalse(index.isWatched(preview(id: "tt9", type: "movie")))
    }

    func testTitleMarkedSeriesTicksLikeTheHoldMenu() {
        let index = WatchedBadgeIndex()
        index.receive(watchedKeys: [key("series", "tt5")], fullyWatchedSeriesKeys: [])
        XCTAssertTrue(index.isWatched(preview(id: "tt5", type: "series")))
        XCTAssertEqual(index.isWatched(preview(id: "tt5", type: "series")),
                       TitleHoldMenuPolicy.effectiveWatched(titleMarked: true, fullyWatchedSeries: false, isSeries: true))
    }

    func testIdsWithColonsAndMalformedKeys() {
        XCTAssertEqual(WatchedBadgeSnapshot.titleKey(fromWatchedKey: key("series", "kitsu:123")), "series|kitsu:123")
        XCTAssertNil(WatchedBadgeSnapshot.titleKey(fromWatchedKey: key("series", "kitsu:123", season: 1, episode: 4)))
        XCTAssertNil(WatchedBadgeSnapshot.titleKey(fromWatchedKey: "garbage"))
        XCTAssertNil(WatchedBadgeSnapshot.titleKey(fromWatchedKey: ":-1:-1"))
        let index = WatchedBadgeIndex()
        index.receive(watchedKeys: [], fullyWatchedSeriesKeys: [key("anime", "kitsu:123")])
        XCTAssertTrue(index.isWatched(preview(id: "kitsu:123", type: "series")))
    }

    func testEmptyFlowsAndResetClear() {
        let index = WatchedBadgeIndex()
        index.receive(watchedKeys: [key("movie", "tt1")], fullyWatchedSeriesKeys: [key("series", "tt2")])
        XCTAssertNotEqual(index.snapshot, .empty)
        // A profile switch / sign-out: the repository republishes both flows empty.
        index.receive(watchedKeys: [], fullyWatchedSeriesKeys: [])
        XCTAssertEqual(index.snapshot, .empty)
        index.receive(watchedKeys: [key("movie", "tt1")], fullyWatchedSeriesKeys: nil)
        index.reset()
        XCTAssertEqual(index.snapshot, .empty)
        XCTAssertFalse(index.isWatched(preview(id: "tt1", type: "movie")))
    }

    func testUnchangedRepublishKeepsTheSnapshot() {
        let index = WatchedBadgeIndex()
        index.receive(watchedKeys: [key("movie", "tt1")], fullyWatchedSeriesKeys: [])
        let before = index.snapshot
        // An episode mark changes the raw keys but no title-level answer.
        index.receive(watchedKeys: [key("movie", "tt1"), key("series", "tt4", season: 2, episode: 1)],
                      fullyWatchedSeriesKeys: nil)
        XCTAssertEqual(index.snapshot, before)
    }
}
