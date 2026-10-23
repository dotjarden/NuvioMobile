import XCTest
@testable import NuvioTV

/// BUG-223 (2026-10-22): the FEAT-15 panel's seed waits for the catalog rows after the rows gate
/// opens; `HomeCatalogSeedSettle.settles` says when that wait is over (the backstop timer is the
/// view model's own).
final class HomeCatalogSeedSettleTests: XCTestCase {
    func testACatalogRowSettlesWhateverTheAddonsSay() {
        XCTAssertTrue(HomeCatalogSeedSettle.settles(hasCatalogRow: true, addonsSettled: false, addonCatalogCount: 8))
        XCTAssertTrue(HomeCatalogSeedSettle.settles(hasCatalogRow: true, addonsSettled: true, addonCatalogCount: 0))
    }

    func testCatalogsStillComingHoldTheSeed() {
        // The fixture's launch: add-ons settled with 8 catalogs, none published yet.
        XCTAssertFalse(HomeCatalogSeedSettle.settles(hasCatalogRow: false, addonsSettled: true, addonCatalogCount: 8))
        // Bootstrap not settled: nothing is known yet, keep holding.
        XCTAssertFalse(HomeCatalogSeedSettle.settles(hasCatalogRow: false, addonsSettled: false, addonCatalogCount: 0))
    }

    func testNoCatalogsAtAllSettlesSoACWOnlyHomeSeeds() {
        XCTAssertTrue(HomeCatalogSeedSettle.settles(hasCatalogRow: false, addonsSettled: true, addonCatalogCount: 0))
    }

    func testAFinishedLoadWithNoCatalogRowSettles() {
        // Review P2-2: eight catalogs in the manifests, all hidden or extras-only; the refresh ran
        // and finished with no row.
        XCTAssertTrue(HomeCatalogSeedSettle.settles(hasCatalogRow: false, addonsSettled: true, addonCatalogCount: 8, loadFinishedEmpty: true))
        XCTAssertFalse(HomeCatalogSeedSettle.settles(hasCatalogRow: false, addonsSettled: true, addonCatalogCount: 8, loadFinishedEmpty: false))
    }
}
