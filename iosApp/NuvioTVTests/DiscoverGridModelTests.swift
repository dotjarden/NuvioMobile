import XCTest
import SharedCore
@testable import NuvioTV

/// FEAT-73 (Steven rc4, D11): the grid-first Discover page's pure rules (`DiscoverGridPlan`) and its
/// view model: the default catalog and remembered genre on first sources, picks (what persists and
/// what doesn't), paging with `skip`, a late page dropped after a selection change, and the
/// failed / empty states.
@MainActor
final class DiscoverGridModelTests: XCTestCase {

    // MARK: - Fixtures

    private func option(_ key: String, type: String = "movie", genres: [String] = [],
                        required: Bool = false, paging: Bool = true) -> DiscoverCatalogOption {
        DiscoverCatalogOption(key: key,
                              addonName: "Cinemeta",
                              manifestUrl: "https://cinemeta.example/manifest.json",
                              type: type,
                              catalogId: "cat-\(key)",
                              catalogName: "Popular \(key)",
                              genreOptions: genres,
                              genreRequired: required,
                              supportsPagination: paging)
    }

    private func item(_ id: String) -> MetaPreview {
        MetaPreview(
            id: id, type: "movie", name: "Title \(id)",
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

    private func page(_ ids: [String], skip: Int, more: Bool) -> CatalogPage {
        CatalogPage(items: ids.map(item),
                    rawItemCount: Int32(ids.count),
                    nextSkip: more ? KotlinInt(int: Int32(skip + ids.count)) : nil)
    }

    /// Fetches held until the test releases them, keyed "<catalog>|<genre>|<skip>".
    @MainActor
    final class GatedFetcher {
        var calls: [String] = []
        private var waiting: [String: [CheckedContinuation<CatalogPage, Error>]] = [:]

        func fetch(_ option: DiscoverCatalogOption, _ genre: String?, _ skip: Int?) async throws -> CatalogPage {
            let key = "\(option.key)|\(genre ?? "*")|\(skip ?? 0)"
            calls.append(key)
            return try await withCheckedThrowingContinuation { continuation in
                waiting[key, default: []].append(continuation)
            }
        }

        func release(_ key: String, _ page: CatalogPage) {
            let continuations = waiting[key] ?? []
            waiting[key] = nil
            continuations.forEach { $0.resume(returning: page) }
        }

        func fail(_ key: String) {
            let continuations = waiting[key] ?? []
            waiting[key] = nil
            continuations.forEach { $0.resume(throwing: URLError(.notConnectedToInternet)) }
        }
    }

    private struct Saved: Equatable {
        let key: String
        let genre: String?
    }

    private func makeModel(_ fetcher: GatedFetcher,
                           persistedKey: String? = nil,
                           remembered: [String: String] = [:]) -> (DiscoverGridViewModel, () -> [Saved]) {
        var saved: [Saved] = []
        let services = DiscoverGridServices(
            fetch: { option, genre, skip, _ in try await fetcher.fetch(option, genre, skip) },
            defaultCatalogKey: { options, type in
                DiscoverSources.shared.gridDefaultCatalog(options: options, type: type,
                                                          preferredCatalogKey: persistedKey)?.key
            },
            rememberedGenre: { option in
                DiscoverGridPlan.resolvedGenre(remembered[option.key], for: option)
            },
            save: { option, genre in saved.append(Saved(key: option.key, genre: genre)) }
        )
        return (DiscoverGridViewModel(services: services), { saved })
    }

    private func drain() async {
        for _ in 0..<6 { await Task.yield() }
    }

    // MARK: - Plan

    func testGenreChoices() {
        XCTAssertNil(DiscoverGridPlan.genreChoices(option("a")))
        XCTAssertEqual(DiscoverGridPlan.genreChoices(option("a", genres: ["Action", "Drama"])),
                       [DiscoverGridPlan.allGenre, "Action", "Drama"])
        XCTAssertEqual(DiscoverGridPlan.genreChoices(option("a", genres: ["Action", " "], required: true)),
                       ["Action"])
    }

    func testResolvedGenre() {
        let optional = option("a", genres: ["Action"])
        let required = option("b", genres: ["Action", "Drama"], required: true)
        XCTAssertNil(DiscoverGridPlan.resolvedGenre(nil, for: optional))
        XCTAssertNil(DiscoverGridPlan.resolvedGenre("Gone", for: optional))
        XCTAssertEqual(DiscoverGridPlan.resolvedGenre("Action", for: optional), "Action")
        XCTAssertEqual(DiscoverGridPlan.resolvedGenre(nil, for: required), "Action")
        XCTAssertEqual(DiscoverGridPlan.resolvedGenre("Drama", for: required), "Drama")
        XCTAssertNil(DiscoverGridPlan.resolvedGenre("Action", for: option("c")))
    }

    func testPillValueRoundTrip() {
        XCTAssertEqual(DiscoverGridPlan.pillValue(nil), DiscoverGridPlan.allGenre)
        XCTAssertNil(DiscoverGridPlan.genre(fromPill: DiscoverGridPlan.allGenre))
        XCTAssertEqual(DiscoverGridPlan.genre(fromPill: "Drama"), "Drama")
    }

    func testShouldLoadMore() {
        XCTAssertFalse(DiscoverGridPlan.shouldLoadMore(index: 10, count: 40))
        XCTAssertTrue(DiscoverGridPlan.shouldLoadMore(index: 32, count: 40))
        XCTAssertTrue(DiscoverGridPlan.shouldLoadMore(index: 0, count: 3))
    }

    // MARK: - View model

    func testFirstSourcesOpenTheDefaultCatalogWithItsRememberedGenre() async {
        let fetcher = GatedFetcher()
        let plain = option("plain")
        let genres = option("genres", genres: ["Action", "Drama"])
        let (model, saved) = makeModel(fetcher, remembered: ["genres": "Drama"])
        model.applySources(options: [plain, genres], state: .ready)
        await drain()
        XCTAssertEqual(model.selectedCatalogKey, "genres")
        XCTAssertEqual(model.selectedGenre, "Drama")
        XCTAssertEqual(model.phase, .loading)
        XCTAssertEqual(fetcher.calls, ["genres|Drama|0"])
        XCTAssertEqual(saved(), [], "a default is not an explicit pick")

        fetcher.release("genres|Drama|0", page(["a", "b"], skip: 0, more: false))
        await drain()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.items.map(\.id), ["a", "b"])
        XCTAssertFalse(model.canLoadMore)
    }

    func testPersistedPickWins() async {
        let fetcher = GatedFetcher()
        let (model, _) = makeModel(fetcher, persistedKey: "plain")
        model.applySources(options: [option("plain"), option("genres", genres: ["Action"])], state: .ready)
        await drain()
        XCTAssertEqual(model.selectedCatalogKey, "plain")
        XCTAssertEqual(fetcher.calls, ["plain|*|0"])
    }

    func testPagingMergesAndStopsAtTheEnd() async {
        let fetcher = GatedFetcher()
        let (model, _) = makeModel(fetcher)
        model.applySources(options: [option("m")], state: .ready)
        await drain()
        fetcher.release("m|*|0", page((0..<10).map { "i\($0)" }, skip: 0, more: true))
        await drain()
        XCTAssertTrue(model.canLoadMore)

        model.itemAppeared(at: 0)   // far from the end: nothing
        await drain()
        XCTAssertEqual(fetcher.calls, ["m|*|0"])

        model.itemAppeared(at: 5)
        await drain()
        XCTAssertEqual(fetcher.calls, ["m|*|0", "m|*|10"])
        XCTAssertTrue(model.isLoadingMore)
        model.itemAppeared(at: 9)   // one page at a time
        await drain()
        XCTAssertEqual(fetcher.calls.count, 2)

        // A duplicate title is merged away.
        fetcher.release("m|*|10", page(["i9", "j1"], skip: 10, more: false))
        await drain()
        XCTAssertEqual(model.items.count, 11)
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertFalse(model.canLoadMore)
    }

    func testGenrePickPersistsAndALatePageNeverLands() async {
        let fetcher = GatedFetcher()
        let genres = option("g", genres: ["Action", "Drama"])
        let (model, saved) = makeModel(fetcher)
        model.applySources(options: [genres], state: .ready)
        await drain()
        XCTAssertEqual(fetcher.calls, ["g|*|0"])
        let firstKey = model.gridKey

        model.select(genrePill: "Drama")
        await drain()
        XCTAssertEqual(saved(), [Saved(key: "g", genre: "Drama")])
        XCTAssertEqual(model.selectedGenre, "Drama")
        XCTAssertNotEqual(model.gridKey, firstKey)

        // The "All" page resolves late: it must not land on the Drama grid.
        fetcher.release("g|*|0", page(["late"], skip: 0, more: false))
        await drain()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.phase, .loading)

        fetcher.release("g|Drama|0", page(["d"], skip: 0, more: false))
        await drain()
        XCTAssertEqual(model.items.map(\.id), ["d"])
    }

    func testTypePickPersistsNothingAndCatalogPickDoes() async {
        let fetcher = GatedFetcher()
        let movies = option("m", genres: ["Action"])
        let movies2 = option("m2")
        let series = option("s", type: "series")
        let (model, saved) = makeModel(fetcher)
        model.applySources(options: [movies, movies2, series], state: .ready)
        await drain()
        model.select(type: "series")
        await drain()
        XCTAssertEqual(model.selectedType, "series")
        XCTAssertEqual(saved(), [])
        model.select(type: "movie")
        await drain()
        XCTAssertEqual(model.selectedCatalogKey, "m", "the type's catalog this session")
        model.select(catalogKey: "m2")
        await drain()
        XCTAssertEqual(saved(), [Saved(key: "m2", genre: nil)])
    }

    func testFailedThenRetryAndEmpty() async {
        let fetcher = GatedFetcher()
        let (model, _) = makeModel(fetcher)
        model.applySources(options: [option("m")], state: .ready)
        await drain()
        fetcher.fail("m|*|0")
        await drain()
        XCTAssertEqual(model.phase, .failed)
        model.retry()
        await drain()
        XCTAssertEqual(model.phase, .loading)
        XCTAssertEqual(fetcher.calls, ["m|*|0", "m|*|0"])
        fetcher.release("m|*|0", page([], skip: 0, more: false))
        await drain()
        XCTAssertEqual(model.phase, .empty)
    }

    func testNoOptionsClearsTheSelection() async {
        let fetcher = GatedFetcher()
        let (model, _) = makeModel(fetcher)
        model.applySources(options: [option("m")], state: .ready)
        await drain()
        model.applySources(options: [], state: .noAddons)
        await drain()
        XCTAssertNil(model.selectedType)
        XCTAssertEqual(model.gridKey, "")
        XCTAssertEqual(model.sourcesState, .noAddons)
    }
}
