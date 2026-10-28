import XCTest
import SharedCore
@testable import NuvioTV

/// `StreamsViewModel.factsCache`: parsed facts are kept by row key across add-on republishes, so
/// only streams not seen before are parsed, and the rows are the same as a direct parse builds.
@MainActor
final class StreamFactsCacheTests: XCTestCase {

    private let hints = StreamBehaviorHints(bingeGroup: nil, notWebReady: false, videoHash: nil, videoSize: nil,
                                            filename: nil, proxyHeaders: nil, audioDelayMs: nil)

    private func stream(_ name: String, addonId: String = "a") -> StreamItem {
        let slug = name.replacingOccurrences(of: " ", with: "-")
        return StreamItem(
            name: name, title: nil, description: nil, url: "https://cdn.example.com/\(addonId)/\(slug).mkv",
            infoHash: nil, fileIdx: nil, externalUrl: nil, ytId: nil, sources: [], sourceName: nil,
            addonName: "Add \(addonId)", addonId: addonId, addonLogo: nil, streamType: nil, behaviorHints: hints,
            clientResolve: nil, debridCacheStatus: nil, externalSubtitles: [], badges: []
        )
    }

    private func group(_ names: [String], loading: Bool = false) -> AddonStreamGroup {
        AddonStreamGroup(addonName: "Add a", addonId: "a", streams: names.map { stream($0) },
                         isLoading: loading, error: nil)
    }

    private func state(_ groups: [AddonStreamGroup]) -> StreamsUiState {
        StreamsUiState(
            requestToken: "t", groups: groups, activeAddonIds: [], installedAddonIds: [],
            selectedFilter: nil, isAnyLoading: false, emptyStateReason: nil, autoPlayStream: nil,
            autoPlayCandidates: [], isDirectAutoPlayFlow: false, showDirectAutoPlayOverlay: false,
            overlayMessage: nil
        )
    }

    private func rows(_ vm: StreamsViewModel) -> [StreamRowModel] { vm.groups.flatMap(\.rows) }

    func testARepublishOfTheSameStreamsParsesNothing() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([group(["One 1080p", "Two 720p", "Three"])]))
        XCTAssertEqual(vm.factsCache.missCount, 3)
        // A different group name forces the group to rebuild; the facts must still come from the cache.
        let renamed = AddonStreamGroup(addonName: "Renamed", addonId: "a",
                                       streams: ["One 1080p", "Two 720p", "Three"].map { stream($0) },
                                       isLoading: false, error: nil)
        vm.apply(state([renamed]))
        XCTAssertEqual(vm.factsCache.missCount, 3, "no row parsed again")
        XCTAssertEqual(rows(vm).count, 3)
    }

    func testAppendingStreamsParsesOnlyTheNewOnes() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([group(["One 1080p", "Two 720p"], loading: true)]))
        let before = Dictionary(uniqueKeysWithValues: rows(vm).map { ($0.key, $0) })
        XCTAssertEqual(vm.factsCache.missCount, 2)

        vm.apply(state([group(["One 1080p", "Two 720p", "Three 2160p", "Four"])]))
        XCTAssertEqual(vm.factsCache.missCount, 4, "only the two appended streams were parsed")
        let after = rows(vm)
        XCTAssertEqual(after.count, 4)
        for (key, old) in before {
            XCTAssertEqual(after.first { $0.key == key }, old, "an existing row is unchanged")
        }
    }

    func testANewLoadClearsTheCache() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([group(["One 1080p", "Two 720p"])]))
        XCTAssertEqual(vm.factsCache.missCount, 2)
        vm.resetForNewLoad()
        XCTAssertEqual(vm.factsCache.missCount, 0)
        let renamed = AddonStreamGroup(addonName: "Renamed", addonId: "a",
                                       streams: ["One 1080p", "Two 720p"].map { stream($0) },
                                       isLoading: false, error: nil)
        vm.apply(state([renamed]))
        XCTAssertEqual(vm.factsCache.missCount, 2, "every row is parsed again after the reset")
    }

    func testCachedRowsEqualRowsBuiltByParsingDirectly() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        let names = ["One 1080p", "Two 2160p", "Three"]
        vm.apply(state([group(names)]))
        vm.apply(state([group(names + ["Four 720p"])]))
        let display = StreamRowDisplay(showFileSize: vm.showFileSizeBadges, badgesOnTop: vm.badgesOnTop,
                                       showAddonLogo: vm.showAddonLogo, instantSuffix: false)
        let g = vm.groups[0]
        for (index, built) in g.rows.enumerated() {
            let direct = StreamRowModel.make(stream: g.streams[index],
                                             facts: StreamFactsParser.shared.parse(stream: g.streams[index]),
                                             key: g.rowKeys[index], display: display)
            XCTAssertEqual(built, direct)
        }
    }
}
