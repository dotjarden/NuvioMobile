import Combine
import XCTest
import SharedCore
@testable import NuvioTV

/// W3-16 (BUG-207, Steven rc11: "stream selection page: scrolling isn't smooth"): the stream picker's
/// rows are plain values (`StreamRowModel`) behind an `Equatable` row view, built once in
/// `StreamsViewModel.apply(_:)`. These pin the two things that make that safe: `==` sees every input
/// that changes what a row draws (a row skipped on a stale model would freeze the spinner, the
/// rejected caption, the badge settings, the Instant-suffix title or the player menu), and an
/// identical republish costs the picker nothing.
@MainActor
final class StreamRowModelTests: XCTestCase {

    // MARK: - Builders

    private func hints(size: Int64? = nil) -> StreamBehaviorHints {
        StreamBehaviorHints(bingeGroup: nil, notWebReady: false, videoHash: nil,
                            videoSize: size.map { KotlinLong(value: $0) }, filename: nil,
                            proxyHeaders: nil, audioDelayMs: nil)
    }

    private func stream(
        name: String? = "Torrentio 4K",
        description: String? = "Movie.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HEVC-GROUP",
        url: String? = "https://cdn.example.com/movie.mkv",
        ytId: String? = nil,
        addonId: String = "addon:x",
        addonName: String = "Add-on",
        addonLogo: String? = nil,
        size: Int64? = nil,
        badges: [StreamBadge] = [],
        cache: StreamDebridCacheStatus? = nil
    ) -> StreamItem {
        StreamItem(
            name: name, title: nil, description: description, url: url, infoHash: nil, fileIdx: nil,
            externalUrl: nil, ytId: ytId, sources: [], sourceName: nil, addonName: addonName, addonId: addonId,
            addonLogo: addonLogo, streamType: nil, behaviorHints: hints(size: size),
            clientResolve: nil, debridCacheStatus: cache, externalSubtitles: [], badges: badges
        )
    }

    private func badge(_ name: String, image: String = "") -> StreamBadge {
        StreamBadge(name: name, imageURL: image, tagColor: "#222222", tagStyle: "filled",
                    textColor: "#FFFFFF", borderColor: "")
    }

    private func cached(provider: String = "rd", name: String = "Real-Debrid") -> StreamDebridCacheStatus {
        StreamDebridCacheStatus(providerId: provider, providerName: name, state: .cached,
                                cachedName: nil, cachedSize: nil)
    }

    private func make(_ stream: StreamItem, key: String = "addon:x#k",
                      display: StreamRowDisplay = StreamRowDisplay()) -> StreamRowModel {
        StreamRowModel.make(stream: stream, key: key, display: display,
                            providerLabel: { $0.providerName })
    }

    // MARK: - make

    func testMakeCarriesWhatTheRowDraws() {
        let s = stream(addonLogo: "https://cdn.example.com/logo.png", size: 3_000_000_000,
                       badges: [badge("4K"), badge("DV", image: "https://cdn.example.com/dv.png")])
        let model = make(s, display: StreamRowDisplay(showFileSize: true, badgesOnTop: true,
                                                      showAddonLogo: true, instantSuffix: false))
        XCTAssertEqual(model.key, "addon:x#k")
        XCTAssertEqual(model.id, "addon:x#k")
        XCTAssertEqual(model.title, "Torrentio 4K")
        XCTAssertEqual(model.description, "Movie.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HEVC-GROUP")
        XCTAssertEqual(model.badges.map(\.name), ["4K", "DV"])
        XCTAssertEqual(model.badges[1].imageURL, "https://cdn.example.com/dv.png")
        XCTAssertEqual(model.sizeBytes, 3_000_000_000)
        XCTAssertTrue(model.badgesOnTop)
        XCTAssertTrue(model.showsAddonColumn)
        XCTAssertEqual(model.addonName, "Add-on")
        XCTAssertEqual(model.addonLogo, "https://cdn.example.com/logo.png")
        XCTAssertFalse(model.isYouTube)
        XCTAssertEqual(model.playbackKey, s.playbackStreamKey)
        XCTAssertFalse(model.playbackKey.isEmpty)
        XCTAssertTrue(model.hasBadgeRow)
        // The four view-state inputs start empty.
        XCTAssertFalse(model.isResolving)
        XCTAssertFalse(model.failedRecently)
        XCTAssertTrue(model.players.isEmpty)
        XCTAssertNil(model.defaultPlayerId)
    }

    func testAnEmptyDescriptionAndLogoBecomeNil() {
        let model = make(stream(description: "", addonLogo: ""))
        XCTAssertNil(model.description)
        XCTAssertNil(model.addonLogo)
        XCTAssertNil(make(stream(description: nil)).description)
    }

    func testTheSizeChipFollowsTheSettingAndTheStream() {
        let sized = stream(size: 1_000_000)
        XCTAssertEqual(make(sized, display: StreamRowDisplay(showFileSize: true)).sizeBytes, 1_000_000)
        XCTAssertNil(make(sized, display: StreamRowDisplay(showFileSize: false)).sizeBytes,
                     "the size chip is off: no size, so no chip")
        XCTAssertNil(make(stream(size: nil), display: StreamRowDisplay(showFileSize: true)).sizeBytes)
        XCTAssertFalse(make(stream(size: nil)).hasBadgeRow, "no badges and no size: no badge row")
        XCTAssertTrue(make(stream(size: 5)).hasBadgeRow)
        XCTAssertTrue(make(stream(badges: [badge("HDR")])).hasBadgeRow)
    }

    func testAYouTubeOnlyStreamIsFlagged() {
        let yt = stream(url: nil, ytId: "dQw4w9WgXcQ")
        XCTAssertTrue(make(yt).isYouTube)
        XCTAssertFalse(make(stream(url: "https://cdn.example.com/a.mkv", ytId: "dQw4w9WgXcQ")).isYouTube)
    }

    // MARK: - The Instant suffix

    func testTheInstantSuffixNeedsTheSettingACachedStatusAndAProviderName() {
        let plain = stream(cache: nil)
        let hit = stream(cache: cached())
        XCTAssertEqual(StreamRowModel.title(for: hit, instantSuffix: false, providerLabel: { $0.providerName }),
                       "Torrentio 4K")
        XCTAssertEqual(StreamRowModel.title(for: plain, instantSuffix: true, providerLabel: { $0.providerName }),
                       "Torrentio 4K")
        let suffixed = StreamRowModel.title(for: hit, instantSuffix: true, providerLabel: { $0.providerName })
        XCTAssertTrue(suffixed.hasPrefix("Torrentio 4K"), suffixed)
        XCTAssertTrue(suffixed.contains("Real-Debrid"), suffixed)
        XCTAssertTrue(suffixed.contains("Instant"), suffixed)
        // No provider name to show: the plain title.
        XCTAssertEqual(StreamRowModel.title(for: hit, instantSuffix: true, providerLabel: { _ in "" }),
                       "Torrentio 4K")
        // A status that is not CACHED never gets the suffix.
        let checking = StreamDebridCacheStatus(providerId: "rd", providerName: "Real-Debrid", state: .checking,
                                               cachedName: nil, cachedSize: nil)
        XCTAssertEqual(StreamRowModel.title(for: stream(cache: checking), instantSuffix: true,
                                            providerLabel: { $0.providerName }), "Torrentio 4K")
    }

    // MARK: - ==

    private func base() -> StreamRowModel {
        make(stream(size: 2_000_000_000, badges: [badge("4K")]))
    }

    func testEqualInputsGiveEqualModels() {
        XCTAssertEqual(base(), base())
        // A rebuilt-from-fresh-Kotlin-objects model compares equal too (the republish case).
        XCTAssertEqual(make(stream(size: 2_000_000_000, badges: [badge("4K")])),
                       make(stream(size: 2_000_000_000, badges: [badge("4K")])))
    }

    func testTheSpinnerIsPartOfEquality() {
        let idle = base().applying(isResolving: false, failedRecently: false, players: [], defaultPlayerId: nil)
        let busy = base().applying(isResolving: true, failedRecently: false, players: [], defaultPlayerId: nil)
        XCTAssertNotEqual(idle, busy)
        XCTAssertTrue(busy.isResolving)
    }

    func testTheRejectedFlagIsPartOfEquality() {
        let ok = base().applying(isResolving: false, failedRecently: false, players: [], defaultPlayerId: nil)
        let failed = base().applying(isResolving: false, failedRecently: true, players: [], defaultPlayerId: nil)
        XCTAssertNotEqual(ok, failed)
        XCTAssertTrue(failed.failedRecently)
    }

    func testTheBadgeSettingsArePartOfEquality() {
        let s = stream(addonLogo: "https://cdn.example.com/l.png", size: 2_000_000_000, badges: [badge("4K")])
        let defaults = make(s)
        XCTAssertNotEqual(defaults, make(s, display: StreamRowDisplay(showFileSize: false)), "file-size chip")
        XCTAssertNotEqual(defaults, make(s, display: StreamRowDisplay(badgesOnTop: true)), "placement")
        XCTAssertNotEqual(defaults, make(s, display: StreamRowDisplay(showAddonLogo: true)), "add-on column")
    }

    func testTheInstantSuffixTitleIsPartOfEquality() {
        let hit = stream(cache: cached())
        let off = StreamRowModel.make(stream: hit, key: "k", display: StreamRowDisplay(instantSuffix: false),
                                      providerLabel: { $0.providerName })
        let on = StreamRowModel.make(stream: hit, key: "k", display: StreamRowDisplay(instantSuffix: true),
                                     providerLabel: { $0.providerName })
        XCTAssertNotEqual(off.title, on.title)
        XCTAssertNotEqual(off, on)
    }

    func testThePlayerListAndItsDefaultArePartOfEquality() {
        let infuse = StreamRowPlayer(id: "infuse", name: "Infuse")
        let vlc = StreamRowPlayer(id: "vlc", name: "VLC")
        func with(_ players: [StreamRowPlayer], _ defaultId: String?) -> StreamRowModel {
            base().applying(isResolving: false, failedRecently: false, players: players, defaultPlayerId: defaultId)
        }
        XCTAssertEqual(with([infuse], nil), with([infuse], nil))
        XCTAssertNotEqual(with([], nil), with([infuse], nil), "a player was installed")
        XCTAssertNotEqual(with([infuse], nil), with([infuse, vlc], nil), "a second player")
        XCTAssertNotEqual(with([infuse, vlc], nil), with([vlc, infuse], nil), "order is the menu's order")
        XCTAssertNotEqual(with([infuse], nil), with([infuse], "infuse"), "the default changed")
    }

    func testTheKeyTitleDescriptionAndBadgesArePartOfEquality() {
        XCTAssertNotEqual(base(), make(stream(size: 2_000_000_000, badges: [badge("4K")]), key: "addon:x#other"))
        XCTAssertNotEqual(base(), make(stream(name: "Other", size: 2_000_000_000, badges: [badge("4K")])))
        XCTAssertNotEqual(base(), make(stream(description: "Other.Release", size: 2_000_000_000, badges: [badge("4K")])))
        XCTAssertNotEqual(base(), make(stream(size: 2_000_000_000, badges: [badge("HDR")])))
        XCTAssertNotEqual(base(), make(stream(size: 2_000_000_000, badges: [])))
    }

    func testTheRowViewComparesOnlyItsModel() {
        let a = StreamRowView(model: base(), onSelect: {}, onBuiltIn: {}, onExternal: { _ in })
        let b = StreamRowView(model: base(), onSelect: { _ = 1 }, onBuiltIn: {}, onExternal: { _ in })
        XCTAssertTrue(a == b, "the closures are not part of the row's identity")
        let busy = StreamRowView(model: base().applying(isResolving: true, failedRecently: false, players: [],
                                                         defaultPlayerId: nil),
                                 onSelect: {}, onBuiltIn: {}, onExternal: { _ in })
        XCTAssertFalse(a == busy)
    }

    // MARK: - StreamsViewModel.apply (F4)

    private func state(_ groups: [AddonStreamGroup], loading: Bool = false) -> StreamsUiState {
        StreamsUiState(
            requestToken: "t", groups: groups, activeAddonIds: [], installedAddonIds: ["addon:x"],
            selectedFilter: nil, isAnyLoading: loading, emptyStateReason: nil, autoPlayStream: nil,
            autoPlayCandidates: [], isDirectAutoPlayFlow: false, showDirectAutoPlayOverlay: false,
            overlayMessage: nil
        )
    }

    private func addonGroup(_ streams: [StreamItem], id: String = "addon:x", loading: Bool = false) -> AddonStreamGroup {
        AddonStreamGroup(addonName: "Add-on", addonId: id, streams: streams, isLoading: loading, error: nil)
    }

    private func twoStreams(url: String = "https://cdn.example.com/b.mkv") -> [StreamItem] {
        [stream(name: "A", description: "A.release", url: "https://cdn.example.com/a.mkv"),
         stream(name: "B", description: "B.release", url: url)]
    }

    func testApplyBuildsOneRowAndKeyPerStream() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([addonGroup(twoStreams())]))
        XCTAssertEqual(vm.groups.count, 1)
        let g = vm.groups[0]
        XCTAssertEqual(g.streams.count, 2)
        XCTAssertEqual(g.rows.count, 2)
        XCTAssertEqual(g.rowKeys.count, 2)
        XCTAssertEqual(g.rows.map(\.key), g.rowKeys, "the rows carry the focus keys")
        XCTAssertEqual(Set(g.rowKeys).count, 2)
        XCTAssertEqual(vm.firstRowKey, g.rowKeys.first)
        XCTAssertEqual(g.rows.map(\.title), ["A", "B"])
    }

    func testAnIdenticalRepublishPublishesNothing() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        var sends = 0
        let sub = vm.objectWillChange.sink { sends += 1 }
        defer { sub.cancel() }

        vm.apply(state([addonGroup(twoStreams())]))
        XCTAssertGreaterThan(sends, 0, "the first emission publishes the list")
        let afterFirst = sends

        // The same list again, from fresh Kotlin objects: a streaming add-on re-emits like this.
        vm.apply(state([addonGroup(twoStreams())]))
        XCTAssertEqual(sends, afterFirst, "an equal list must not invalidate the picker")
    }

    func testARowKeepsItsKeyAcrossRepublishes() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([addonGroup(twoStreams())], loading: true))
        let keys = vm.groups[0].rowKeys
        // A second add-on streams in and the first one finishes.
        vm.apply(state([addonGroup(twoStreams()), addonGroup([stream(name: "C", description: "C.release",
                                                                     url: "https://cdn.example.com/c.mkv",
                                                                     addonId: "addon:y")], id: "addon:y")],
                          loading: false))
        XCTAssertEqual(vm.groups.count, 2)
        XCTAssertEqual(vm.groups[0].rowKeys, keys, "initial focus and restore rely on stable keys")
    }

    func testALoadingFlipRepublishesButReusesTheRows() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        var sends = 0
        let sub = vm.objectWillChange.sink { sends += 1 }
        defer { sub.cancel() }
        vm.apply(state([addonGroup(twoStreams(), loading: true)], loading: true))
        let rows = vm.groups[0].rows
        XCTAssertTrue(vm.groups[0].isLoading)
        let before = sends

        vm.apply(state([addonGroup(twoStreams(), loading: false)], loading: false))
        XCTAssertGreaterThan(sends, before, "the header spinner must go")
        XCTAssertFalse(vm.groups[0].isLoading)
        XCTAssertEqual(vm.groups[0].rows, rows)
    }

    /// A debrid preparation swaps a resolved URL into the same row (same name, description and hash,
    /// so the same key): the list must republish, or a press would play the stale stream.
    func testASwappedStreamUnderTheSameKeyIsRepublished() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([addonGroup(twoStreams(url: "https://cdn.example.com/b.mkv"))]))
        let keys = vm.groups[0].rowKeys

        vm.apply(state([addonGroup(twoStreams(url: "https://cdn.example.com/b-resolved.mkv"))]))
        XCTAssertEqual(vm.groups[0].rowKeys, keys, "same identity, same focus keys")
        let url: String? = vm.groups[0].streams[1].url
        XCTAssertEqual(url, "https://cdn.example.com/b-resolved.mkv")
    }

    func testAnEmptyListClearsTheFirstRowKey() {
        let vm = StreamsViewModel(type: "movie", videoId: "tt1")
        vm.apply(state([addonGroup(twoStreams())]))
        XCTAssertNotNil(vm.firstRowKey)
        vm.apply(state([]))
        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertNil(vm.firstRowKey)
    }
}
