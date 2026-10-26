import XCTest
import SharedCore
@testable import NuvioTV

/// Add-ons hub C, H1: the pure rules behind the hub's summary line and the reorder buttons.
final class AddonsHubSummaryTests: XCTestCase {

    private func manifest(_ id: String, catalogs: Int) -> AddonManifest {
        AddonManifest(
            id: id, name: id, description: "", version: "1.0.0", logoUrl: nil,
            resources: [AddonResource(name: "stream", types: ["movie"], idPrefixes: [])],
            types: ["movie"], idPrefixes: [],
            catalogs: (0..<catalogs).map { AddonCatalog(type: "movie", id: "\(id)-\($0)", name: "Cat \($0)", extra: []) },
            behaviorHints: AddonBehaviorHints(configurable: false, configurationRequired: false, adult: false, p2p: false),
            transportUrl: "https://\(id).example.com"
        )
    }

    private func addon(
        _ id: String, manifest: AddonManifest?, enabled: Bool,
        refreshing: Bool = false, error: String? = nil
    ) -> ManagedAddon {
        ManagedAddon(
            manifestUrl: "https://\(id).example.com/manifest.json", manifest: manifest,
            userSetName: nil, enabled: enabled, isRefreshing: refreshing, errorMessage: error
        )
    }

    private func catalog(_ key: String, enabled: Bool, collection: Bool = false) -> HomeCatalogSettingsItem {
        HomeCatalogSettingsItem(
            key: key, defaultTitle: key, addonName: "Add-on", customTitle: "", enabled: enabled,
            heroSourceEnabled: true, order: 0, isCollection: collection, collectionId: nil, isPinnedToTop: false
        )
    }

    private var addons: [ManagedAddon] {
        [
            addon("a", manifest: manifest("a", catalogs: 2), enabled: true),
            addon("b", manifest: manifest("b", catalogs: 1), enabled: false),
            addon("c", manifest: nil, enabled: true),
        ]
    }

    private var catalogs: [HomeCatalogSettingsItem] {
        [
            catalog("one", enabled: true),
            catalog("two", enabled: true),
            catalog("three", enabled: false),
            catalog("shelf", enabled: true, collection: true),
        ]
    }

    func testSummaryCountsAddonsCatalogsDebridAndPlugins() {
        let summary = AddonsViewModel.summary(
            addons: addons, catalogs: catalogs, debridConnectedNames: ["TorBox"],
            pluginsEnabled: true, pluginRepositories: 2, pluginProviders: 7
        )
        XCTAssertEqual(summary, AddonsViewModel.HubSummary(
            addonsInstalled: 3, addonsOn: 1, catalogsOn: 2, catalogsTotal: 3,
            debridConnected: ["TorBox"],
            plugins: AddonsViewModel.PluginSummary(repositories: 2, providers: 7)
        ))
    }

    func testDisabledPluginsGiveNoPluginSummary() {
        let summary = AddonsViewModel.summary(
            addons: addons, catalogs: catalogs, debridConnectedNames: ["TorBox"],
            pluginsEnabled: false, pluginRepositories: 2, pluginProviders: 7
        )
        XCTAssertNil(summary.plugins)
    }

    func testMoveTarget() {
        XCTAssertNil(AddonsViewModel.moveTarget(index: 0, by: -1, count: 3))
        XCTAssertNil(AddonsViewModel.moveTarget(index: 2, by: 1, count: 3))
        XCTAssertEqual(AddonsViewModel.moveTarget(index: 1, by: 1, count: 3), 2)
        XCTAssertEqual(AddonsViewModel.moveTarget(index: 1, by: -1, count: 3), 0)
        XCTAssertNil(AddonsViewModel.moveTarget(index: 1, by: 0, count: 3))
        XCTAssertNil(AddonsViewModel.moveTarget(index: 5, by: -1, count: 3))
        XCTAssertNil(AddonsViewModel.moveTarget(index: 0, by: 1, count: 0))
    }

    func testRefreshOutcomeCountsErrorsAndMissingAsFailed() {
        let list = [
            addon("a", manifest: manifest("a", catalogs: 1), enabled: true),
            addon("b", manifest: nil, enabled: true, error: "boom"),
            // Still refreshing when the wait gave up: not a success.
            addon("c", manifest: manifest("c", catalogs: 1), enabled: true, refreshing: true),
        ]
        let urls: Set<String> = [
            "https://a.example.com/manifest.json",
            "https://b.example.com/manifest.json",
            "https://c.example.com/manifest.json",
            "https://gone.example.com/manifest.json",
        ]
        XCTAssertEqual(
            AddonsViewModel.refreshOutcome(addons: list, refreshedUrls: urls),
            AddonsViewModel.RefreshOutcome(succeeded: 1, failed: 3)
        )
        XCTAssertEqual(
            AddonsViewModel.refreshOutcome(addons: list, refreshedUrls: []),
            AddonsViewModel.RefreshOutcome(succeeded: 0, failed: 0)
        )
    }

    func testStatusPriority() {
        let m = manifest("a", catalogs: 0)
        XCTAssertEqual(AddonsViewModel.status(of: addon("a", manifest: m, enabled: false, refreshing: true)), .refreshing)
        XCTAssertEqual(AddonsViewModel.status(of: addon("a", manifest: nil, enabled: false, error: "x")), .unavailable)
        XCTAssertEqual(AddonsViewModel.status(of: addon("a", manifest: m, enabled: false, error: "x")), .disabled)
        XCTAssertEqual(AddonsViewModel.status(of: addon("a", manifest: m, enabled: true)), .active)
    }

    func testHostKeepsAnIPv6LiteralAndDropsItsPort() {
        XCTAssertEqual(AddonsViewModel.host(of: "http://[::1]:8080/manifest.json"), "[::1]")
        XCTAssertEqual(AddonsViewModel.host(of: "x.y/a?u=http://z"), "x.y")
    }

    func testHostDropsEverythingButTheHost() {
        XCTAssertEqual(
            AddonsViewModel.host(of: "https://user:pw@Addon.example.com:8080/KEY/manifest.json?token=1"),
            "Addon.example.com"
        )
    }

    func testResourceLabelsMapOrderAndDeduplicate() {
        let m = AddonManifest(
            id: "x", name: "x", description: "", version: "1", logoUrl: nil,
            resources: ["stream", "catalog", "subtitles", "meta", "addon_catalog", "stream"]
                .map { AddonResource(name: $0, types: [], idPrefixes: []) },
            types: [], idPrefixes: [], catalogs: [],
            behaviorHints: AddonBehaviorHints(configurable: false, configurationRequired: false, adult: false, p2p: false),
            transportUrl: "https://x.example.com"
        )
        XCTAssertEqual(
            AddonsViewModel.resourceLabels(of: m),
            ["Streams", "Catalogs", "Subtitles", "Metadata", "Addon catalog"]
        )
    }

    func testLogoUrlsTakeEnabledNonEmptyUpToLimit() {
        func withLogo(_ id: String, _ logo: String?, enabled: Bool = true) -> ManagedAddon {
            let base = manifest(id, catalogs: 0)
            let m = AddonManifest(
                id: base.id, name: base.name, description: "", version: "1", logoUrl: logo,
                resources: base.resources, types: base.types, idPrefixes: [], catalogs: [],
                behaviorHints: base.behaviorHints, transportUrl: base.transportUrl
            )
            return addon(id, manifest: m, enabled: enabled)
        }
        let list = [
            withLogo("a", "https://a/l.png"), withLogo("b", ""), withLogo("c", "https://c/l.png", enabled: false),
            withLogo("d", nil), withLogo("e", "https://e/l.png"), withLogo("f", "https://f/l.png"),
        ]
        XCTAssertEqual(AddonsViewModel.logoUrls(of: list, limit: 2), ["https://a/l.png", "https://e/l.png"])
    }

    /// Review r1: two identical outcomes in a row carry different serials, so `onChange` (which
    /// compares with `==`) fires for the second one. Uses the real view model: an unsupported
    /// scheme fails in the synchronous validation path, with no network.
    @MainActor
    func testRepeatedInstallFailuresGetDifferentSerials() {
        let model = AddonsViewModel()
        model.install("ftp://x.y/a")
        guard case .failed(let firstMessage, let firstSerial)? = model.installOutcome else {
            return XCTFail("first install did not fail: \(String(describing: model.installOutcome))")
        }
        model.install("ftp://x.y/a")
        guard case .failed(let secondMessage, let secondSerial)? = model.installOutcome else {
            return XCTFail("second install did not fail: \(String(describing: model.installOutcome))")
        }
        XCTAssertEqual(firstMessage, secondMessage)
        XCTAssertNotEqual(firstSerial, secondSerial)
    }

    /// Review r2: with no manifest and no user-set name the title is the host, never the URL's
    /// last path segment (which can be a key).
    func testDisplayTitleFallsBackToTheHostWithoutAManifest() {
        let keyed = ManagedAddon(
            manifestUrl: "https://torbox.example.com/torbox=SECRETKEY/manifest.json", manifest: nil,
            userSetName: nil, enabled: true, isRefreshing: false, errorMessage: nil
        )
        XCTAssertEqual(AddonsViewModel.displayTitle(keyed), "torbox.example.com")
        let named = ManagedAddon(
            manifestUrl: keyed.manifestUrl, manifest: nil,
            userSetName: "Mine", enabled: true, isRefreshing: false, errorMessage: nil
        )
        XCTAssertEqual(AddonsViewModel.displayTitle(named), "Mine")
        XCTAssertEqual(
            AddonsViewModel.displayTitle(addon("a", manifest: manifest("a", catalogs: 0), enabled: true)), "a"
        )
    }
}
